abstract type A end
struct B <: A
    i::Int
end

expr1 = :(struct Foo1 i::B end)

class = B
expr2 = :(struct Foo2 i::$class end)

dump(expr1)

dump(expr2)
