module TestClasses

using Test
using Classes

@class Foo <: Class begin
   foo::Int
end

@class mutable Bar <: Foo begin
    bar::Int
end

@class mutable Baz <: Bar begin
   baz::Int
end

@method foo(obj::Foo) = obj.foo

@method function bar(obj::Bar)
    return obj.bar
end

@test Set(subclasses(Foo)) == Set(Any[Bar, Baz])

x = Foo(1)
y = Bar(10, 11)
z = Baz(100, 101, 102)

@test fieldnames(Foo) == (:foo,)
@test fieldnames(Bar) == (:foo, :bar)
@test fieldnames(Baz) == (:foo, :bar, :baz)

@test foo(x) == 1
@test foo(y) == 10
@test foo(z) == 100

@test bar(y) == 11
@test bar(z) == 101

@test_throws Exception bar(x)

# Mutable
z.foo = 1000
@test foo(z) == 1000

# Immutable
@test_throws Exception x.foo = 1000

# test that where clause is amended properly
@method zzz(obj::Foo, bar::T) where {T} = T

@test zzz(x, :x) == Symbol
@test zzz(y, 10.6) == Float64

end # module
