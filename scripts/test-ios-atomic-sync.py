#!/usr/bin/env python3
"""Exercise the real SQL with independent connections in a disposable local DB.
Requires a local PostgreSQL 17 server; never accepts a remote host.
Usage: python3 scripts/test-ios-atomic-sync.py [local-port]
"""
import json
import subprocess
import shutil
import sys
import time
import uuid
from pathlib import Path

PORT = sys.argv[1] if len(sys.argv) > 1 else '55547'
DATABASE = 'earnline_cas_test_' + uuid.uuid4().hex
PSQL = [shutil.which('psql') or '/opt/homebrew/opt/postgresql@17/bin/psql', '-X', '-qAt', '-h', '127.0.0.1', '-p', PORT,
        '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=verbose']
ROOT = Path(__file__).resolve().parents[1]


def sql(query, database=DATABASE, ok=True):
    result = subprocess.run(PSQL + ['-d', database], input=query, text=True, capture_output=True)
    if ok and result.returncode:
        raise AssertionError(result.stderr)
    return result


def rpc(table, rows, versions, force=False):
    return "select public.earnline_upsert_versioned('%s','cas-test',$j$%s$j$,$j$%s$j$,%s);" % (
        table, json.dumps(rows), json.dumps(versions), str(force).lower())


OWNER = str(uuid.uuid4())
AS_OWNER = "set role authenticated; set request.jwt.claim.sub = '%s';" % OWNER


def version(table, key):
    return int(sql("select round(extract(epoch from updated_at)*1000000)::bigint from public.%s where %s;"
                   % (table, key)).stdout.strip())


def assert_conflict(query):
    result = sql(AS_OWNER + query, ok=False)
    assert result.returncode and 'PT409' in result.stderr, result.stderr


def concurrent_update(table, first, second, baseline):
    query = AS_OWNER + "set application_name='earnline_cas_writer';begin;" + rpc(table, [first], [baseline]) + 'select pg_sleep(1); commit; -- cas_writer'
    process = subprocess.Popen(PSQL + ['-d', DATABASE], stdin=subprocess.PIPE,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    process.stdin.write(query)
    process.stdin.close()
    # Wait for the first writer to hold the updated row lock before sending B.
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        active = sql("select count(*) from pg_stat_activity where datname=current_database() "
                     "and wait_event='PgSleep' and application_name='earnline_cas_writer';").stdout.strip()
        if active == '1':
            break
        time.sleep(0.02)
    else:
        raise AssertionError('First writer did not reach the lock checkpoint: ' + process.stderr.read() if process.poll() is not None else 'Writer still running')
    assert_conflict(rpc(table, [second], [baseline]))
    process.wait(timeout=10)
    assert process.returncode == 0, process.stderr.read()


sql('create database ' + DATABASE, database='postgres')
try:
    # Roles already exist on Supabase; local clusters need just these identities.
    sql("do $$begin if not exists(select from pg_roles where rolname='anon') then create role anon; end if; "
        "if not exists(select from pg_roles where rolname='authenticated') then create role authenticated; end if; "
        "if not exists(select from pg_roles where rolname='service_role') then create role service_role; end if; end$$;")
    sql("""create schema auth;
create table auth.users(id uuid primary key, is_anonymous boolean default false,
raw_app_meta_data jsonb default '{}', created_at timestamptz default now(),last_sign_in_at timestamptz);
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
create function auth.jwt() returns jsonb language sql stable as $$select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb$$;
grant usage on schema auth to authenticated,anon;
create publication supabase_realtime;
""")
    for path in sorted((ROOT / 'supabase/migrations').glob('*.sql')):
        source = path.read_text()
        # Scheduler installation is unrelated to sync and unavailable in stock PG.
        source = source.split('create extension if not exists pg_cron')[0]
        sql(source)
    sql("insert into auth.users(id) values('%s'); insert into public.earnline_workspaces(id,owner_id) "
        "values('cas-test','%s'); insert into public.earnline_workspace_members(workspace_id,user_id,role) "
        "values('cas-test','%s','owner');" % (OWNER, OWNER, OWNER))
    client_id, entry_id = str(uuid.uuid4()), str(uuid.uuid4())
    client = dict(id=client_id, workspace_id='cas-test', name='Fixture', color_hex='#123456',
                  sort_index=0, created_at='2026-01-01T00:00:00Z')
    sql(AS_OWNER + rpc('earnline_clients', [client], [None]))
    entry = dict(id=entry_id, workspace_id='cas-test', client_id=client_id, amount='100.00',
                 currency_code='USD', task='Fixture', project=None, date='2026-09-05', hold_until=None,
                 status='paid', sort_index=0, created_at='2026-01-01T00:00:00Z')
    sql(AS_OWNER + rpc('earnline_entries', [entry], [None]))
    baseline = version('earnline_entries', "id='%s'" % entry_id)
    concurrent_update('earnline_entries', {**entry, 'amount': '200'}, {**entry, 'amount': '300'}, baseline)
    assert sql("select amount from earnline_entries where id='%s'" % entry_id).stdout.strip() == '200.00'
    print('PASS: simultaneous entry updates preserve first writer and reject stale second writer')

    # Swift UUID.encode emits uppercase; PostgreSQL uuid::text is lowercase.
    swift_entry = {**entry, 'id': entry_id.upper(), 'client_id': client_id.upper(), 'amount': '210'}
    baseline = version('earnline_entries', "id='%s'" % entry_id)
    sql(AS_OWNER + rpc('earnline_entries', [swift_entry], [baseline]))
    assert_conflict(rpc('earnline_entries', [swift_entry], [baseline]))
    sql(AS_OWNER + rpc('earnline_entries', [{**swift_entry, 'amount': '220'}], [None], force=True))
    assert sql("select amount from earnline_entries where id='%s'" % entry_id).stdout.strip() == '220.00'
    print('PASS: Swift uppercase UUID updates and explicit local conflict choice preserve row identity')

    profile = dict(workspace_id='cas-test', base_currency_code='USD', secondary_currency_code='RUB', exchange_rate='90')
    sql(AS_OWNER + rpc('earnline_profiles', [profile], [None]))
    baseline = version('earnline_profiles', "workspace_id='cas-test'")
    concurrent_update('earnline_profiles', {**profile, 'exchange_rate': '91'}, {**profile, 'exchange_rate': '92'}, baseline)
    print('PASS: simultaneous profile updates report a conflict')

    current = version('earnline_entries', "id='%s'" % entry_id)
    new_entry = {**entry, 'id': str(uuid.uuid4())}
    assert_conflict(rpc('earnline_entries', [new_entry, entry], [None, current - 1]))
    assert sql("select count(*) from earnline_entries where id='%s'" % new_entry['id']).stdout.strip() == '0'
    print('PASS: any stale row rolls back the entire batch')

    sql(AS_OWNER + "insert into earnline_tombstones(id,workspace_id,entity,record_id) values('%s','cas-test','entry','%s'); "
        "delete from earnline_entries where id='%s';" % (uuid.uuid4(), entry_id, entry_id))
    assert_conflict(rpc('earnline_entries', [entry], [current]))
    assert_conflict(rpc('earnline_entries', [entry], [None]))
    sql(AS_OWNER + rpc('earnline_entries', [entry], [None], force=True))
    assert sql("select e.updated_at > t.deleted_at from earnline_entries e join earnline_tombstones t on t.record_id=e.id "
               "where e.id='%s'" % entry_id).stdout.strip() == 't'
    print('PASS: deletion is not silently resurrected; explicit restore gets a newer version')

    stranger = "set role authenticated; set request.jwt.claim.sub='%s';" % uuid.uuid4()
    denied = sql(stranger + rpc('earnline_entries', [entry], [None], True), ok=False)
    assert denied.returncode and '42501' in denied.stderr
    denied = sql('set role anon;' + rpc('earnline_entries', [entry], [None]), ok=False)
    assert denied.returncode and '42501' in denied.stderr
    print('PASS: anonymous and foreign-workspace access denied, including forced writes')
    # Combined reads preserve RLS and return bounded, keyset-paged snapshots.
    def pull(since=None, before=None, done=None, identity=AS_OWNER):
        return sql(identity + "select public.earnline_pull_page('cas-test',$j$%s$j$,$j$%s$j$,ARRAY[%s]::text[]);" % (
            json.dumps(since or {}), json.dumps(before or {}),
            ','.join("'%s'" % name for name in (done or []))))
    page = json.loads(pull().stdout.strip())
    assert len(page['earnline_clients']) == 1 and len(page['earnline_entries']) == 1
    more = [{**entry, 'id': str(uuid.uuid4()), 'task': 'Page %s' % n} for n in range(251)]
    for start in range(0, len(more), 250):
        rows = more[start:start+250]
        sql(AS_OWNER + rpc('earnline_entries', rows, [None]*len(rows)))
    first = json.loads(pull().stdout.strip())['earnline_entries']
    assert len(first) == 250
    last = first[-1]
    second = json.loads(pull(before={'earnline_entries': {'timestamp': last['updated_at'], 'id': last['id']}}).stdout.strip())['earnline_entries']
    assert len(second) == 2 and not ({x['id'] for x in first} & {x['id'] for x in second})
    assert json.loads(pull(done=['earnline_entries']).stdout.strip())['earnline_entries'] == []
    denied = sql(stranger + "select public.earnline_pull_page('cas-test');", ok=False)
    assert denied.returncode and '42501' in denied.stderr
    denied = sql("set role anon;select public.earnline_pull_page('cas-test');", ok=False)
    assert denied.returncode and '42501' in denied.stderr
    print('PASS: bounded combined reads, keyset pagination and caller isolation')

finally:
    sql('drop database ' + DATABASE + ' with (force)', database='postgres')
