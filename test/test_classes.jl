using Test
using Classes

@test superclass(Class) === nothing

@test isclass(AbstractClass) == false       # not concrete
@test isclass(Int) == false                 # not <: AbstractClass

@class Foo begin
   foo::Int

   Foo() = Foo(0)

   # Although Foo is immutable, subclasses might not be,
   # so it's still useful to define this method.
   function Foo(self::AbstractFoo)
        self.foo = 0
    end
end

@test classof(AbstractFoo) == Foo
@test classof(Foo) == Foo

@test superclass(Foo) == Class
@test_throws Exception superclass(AbstractFoo)

@class mutable Bar <: Foo begin
    bar::Int

    # Mutable classes can use this pattern
    function Bar(self::Union{Nothing, AbstractBar}=nothing)
        self = (self === nothing ? new() : self)
        superclass(Bar)(self)
        Bar(self, 0)
    end
end

@class mutable Baz <: Bar begin
   baz::Int

   function Baz(self::Union{Nothing, AbstractBaz}=nothing)
        self = (self === nothing ? new() : self)
        superclass(Baz)(self)
        Baz(self, 0)
    end
end

function sum(obj::AbstractBar)
    return obj.foo + obj.bar
end

@test Set(superclasses(Baz)) == Set([Foo, Bar, Class])
@test Set(subclasses(Foo)) == Set(Any[Bar, Baz])

x = Foo(1)
y = Bar(10, 11)
z = Baz(100, 101, 102)

@test fieldnames(Foo) == (:foo,)
@test fieldnames(Bar) == (:foo, :bar)
@test fieldnames(Baz) == (:foo, :bar, :baz)

foo(x::AbstractFoo) = x.foo

@test foo(x) == 1
@test foo(y) == 10
@test foo(z) == 100

@test sum(y) == 21

get_bar(x::AbstractBar) = x.bar

@test get_bar(y) == 11
@test get_bar(z) == 101

@test_throws Exception get_bar(x)

# Mutable
set_foo!(x::AbstractFoo, value) = (x.foo = value)
set_foo!(z, 1000)
@test foo(z) == 1000

# Immutable
@test_throws Exception x.foo = 1000

# test that where clause is amended properly
zzz(obj::AbstractFoo, bar::T) where {T} = T

@test zzz(x, :x) == Symbol
@test zzz(y, 10.6) == Float64

# Test other @class structural errors
@test_throws(LoadError, eval(Meta.parse("@class X2 x y")))
@test_throws(LoadError, eval(Meta.parse("@class (:junk,)")))

# Test that classof fails if an abstract class has multiple concrete classes
@class Blink <: Baz
struct RenegadeStruct <: AbstractBlink end

@test_throws Exception classof(AbstractBlink)

# Test that parameterized type is handled properly
@class TupleHolder{NT <: NamedTuple} begin
    nt::NT
end

nt = (foo=1, bar=2)
NT = typeof(nt)
th = TupleHolder{NT}(nt)

@test typeof(th).parameters[1] == NT
@test th.nt.foo == 1
@test th.nt.bar == 2

# Test updating using instance of parent class
bar = Bar(1, 2)
baz = Baz(100, 101, 102)

upd = Baz(bar, 555)
@test upd.foo == 1 && upd.bar == 2 && upd.baz == 555

# ...and with parameterized types
@class mutable SubTupleHolder{NT <: NamedTuple} <: Baz begin
    nt::NT
end

sub = SubTupleHolder{NT}(z, nt)
@test sub.nt.foo == 1 && sub.nt.bar == 2 && sub.foo == 1000 && sub.bar == 101 && sub.baz == 102

xyz = SubTupleHolder(sub, 10, 20, 30, (foo=111, bar=222))
@test xyz.nt.foo == 111 && xyz.nt.bar == 222 && xyz.foo == 10

@class Parameterized{T1 <: Foo, T2 <: Foo} begin
    one::T1
    two::T2
end

@class ParameterizedSub{T3 <: TupleHolder, T4 <: TupleHolder} <: Parameterized begin
    x::Float64
    y::Float64
end

# non-constrained struct type parameter
@class mutable AbstractLog{T} begin
    pos::Matrix{T}
end

obj = AbstractLog{Float64}([1. 2.; 3. 4.])

@test obj.pos == [1. 2.; 3. 4.]

# TBD: add tests on these

# Generated: needs work on parameterized types (T1, T2 are not defined)
# - convert param names to gensyms to avoid collisions
#
# function (ParameterizedSub{T3, T4}(one::T1, two::T2, x::Float64, y::Float64; )::Any) where {T3 <: TupleHolder, T4 <: TupleHolder}
#     #= /Users/rjp/.julia/packages/MacroTools/4AjBS/src/utils.jl:302 =#
#     new{T3, T4}(one, two, x, y)
# end