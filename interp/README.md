# js/interp

Runs js/bytecode: the Engine behind every realm's ECMAScript function objects. A call runs a Frame: registers, an accumulator, the current context and the program counter.

```vertex
import "js/interp"
```

## Types

- **`Engine`** (class): Engine runs bytecode for every realm of an agent.

Part of the [`js`](https://github.com/vertex-language/js) repository.
