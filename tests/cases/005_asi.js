// §12.10 Automatic semicolon insertion.
let a = 1
let b = 2
console.log(a + b)
function f() {
  return
  42
}
console.log(f())
let c = a
++b
console.log(c, b)
let i = 0
i++
console.log(i)
const g = function () { return "g" }
;[1, 2].forEach(function (x) { console.log("item", x) })
console.log(g())
