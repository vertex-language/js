// §15.7 private fields, methods, accessors, and `#x in obj`.
class Account {
  #balance = 0;
  static #instances = 0;
  constructor() { Account.#instances++; }
  #log(msg) { return "[" + msg + "]"; }
  get #doubled() { return this.#balance * 2; }
  deposit(n) { this.#balance += n; return this.#log("dep " + n); }
  get balance() { return this.#balance; }
  get doubled() { return this.#doubled; }
  static count() { return Account.#instances; }
  static isAccount(o) { return #balance in o; }
  peek(other) { return other.#balance; }
}
const acc = new Account();
console.log(acc.deposit(50), acc.balance, acc.doubled, Account.count());
console.log(Account.isAccount(acc), Account.isAccount({}), "#balance" in acc);
try { acc.peek({}); } catch (e) { console.log(e.name); }
console.log(new Account().peek(acc), Object.keys(acc).length, JSON.stringify(acc));
try { eval("acc.#balance"); } catch (e) { console.log(e.name); }
class Counter { #n = 0; inc() { return ++this.#n; } }
const k = new Counter(); k.inc();
console.log(k.inc());
