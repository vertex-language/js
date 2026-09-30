// §7.4.11 IteratorClose on early exit from for-of, destructuring, and throw.
function tracked(label) {
  return {
    [Symbol.iterator]() {
      let i = 0;
      return {
        next: () => ({ value: i++, done: i > 5 }),
        return: () => { console.log(label, "closed"); return { done: true }; },
      };
    },
  };
}
for (const x of tracked("break")) { if (x === 1) break; }
try { for (const x of tracked("throw")) { throw new Error("e"); } } catch {}
(function () { for (const x of tracked("return")) return; })();
const [a] = tracked("destructure");
for (const x of tracked("exhaust")) {}
console.log("exhausted without close");
outer: for (const y of [1]) { for (const x of tracked("labeled")) continue outer; }
function* gen() { try { yield 1; yield 2; } finally { console.log("gen finally"); } }
for (const v of gen()) break;
