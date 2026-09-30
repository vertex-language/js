// Integration: event-sourced state machine with classes, maps, JSON, and closures.
class Store {
  #state; #reducers; #log = [];
  constructor(initial, reducers) { this.#state = structuredCloneish(initial); this.#reducers = reducers; }
  dispatch(action) {
    const r = this.#reducers[action.type];
    if (!r) throw new TypeError(`unknown action ${action.type}`);
    this.#state = r(this.#state, action.payload);
    this.#log.push(action.type);
    return this;
  }
  get state() { return this.#state; }
  get history() { return this.#log.join(">"); }
}
function structuredCloneish(v) { return JSON.parse(JSON.stringify(v)); }
const store = new Store({ todos: [], nextId: 1 }, {
  add: (s, text) => ({ ...s, todos: [...s.todos, { id: s.nextId, text, done: false }], nextId: s.nextId + 1 }),
  toggle: (s, id) => ({ ...s, todos: s.todos.map(t => t.id === id ? { ...t, done: !t.done } : t) }),
  clear: s => ({ ...s, todos: s.todos.filter(t => !t.done) }),
});
store.dispatch({ type: "add", payload: "write tests" }).dispatch({ type: "add", payload: "run engine" }).dispatch({ type: "toggle", payload: 1 });
console.log(JSON.stringify(store.state));
store.dispatch({ type: "clear" });
console.log(store.history, store.state.todos.map(t => t.text).join());
try { store.dispatch({ type: "nope" }); } catch (e) { console.log(e.name, e.message); }
const byDone = Map.groupBy(JSON.parse('[{"d":true},{"d":false},{"d":true}]'), t => t.d);
console.log(byDone.get(true).length, byDone.get(false).length);
