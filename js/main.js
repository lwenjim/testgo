var foo = function*(params) {
    try {
        let a  = yield 1
        let b = yield 2
        return 3
    } catch (error) {
        console.log(error)        
    }
}
let b = foo(123)
console.log(b.next())
console.log(b.next())
console.log(b.next())