import { describe, it, expect } from "vitest";
import { deterministicUuid, newUuid } from "./deterministicId";

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

describe("deterministicId", () => {
  it("is stable for the same input", () => {
    const a = deterministicUuid("tombstone:entry:abc");
    const b = deterministicUuid("tombstone:entry:abc");
    expect(a).toBe(b);
  });
  it("differs for different inputs", () => {
    expect(deterministicUuid("a")).not.toBe(deterministicUuid("b"));
  });
  it("produces a well-formed v5-style UUID", () => {
    const id = deterministicUuid("earnline-client:acme studio");
    expect(id).toMatch(UUID_RE);
    expect(id[14]).toBe("5"); // version nibble
    expect(["8", "9", "a", "b"]).toContain(id[19]); // variant
  });
  it("newUuid is a valid UUID", () => {
    expect(newUuid()).toMatch(UUID_RE);
  });
});
