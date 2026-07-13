/** Cancels in-flight work and rejects stale completions after reconfiguration. */
export class SyncGenerationGuard<T extends object> {
  private value = 0;
  private controller: AbortController | null = null;

  get generation(): number { return this.value; }

  begin(resource: T): { generation: number; resource: T; signal: AbortSignal } {
    this.controller?.abort();
    this.controller = new AbortController();
    return { generation: this.value, resource, signal: this.controller.signal };
  }

  isCurrent(attempt: { generation: number; resource: T }, activeResource: T): boolean {
    return attempt.generation === this.value && attempt.resource === activeResource;
  }

  invalidate(): void {
    this.value += 1;
    this.controller?.abort();
    this.controller = null;
  }

  finish(attempt: { generation: number }): void {
    if (attempt.generation === this.value) this.controller = null;
  }
}
