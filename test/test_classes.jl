using Test
using Classes
using Suppressor

@test superclass(Class) === nothing

@class Foo(getter_prefix="") <: Class begin
   foo::Int

   Foo() = Foo(0)

   # Although Foo is immutable, subclasses might not be,
   # so it's still useful to define this method.
   function Foo(self::absclass(Foo))
        self.foo = 0
    end
end

@test classof(AbstractFoo) == Foo
@test classof(Foo) == Foo

@test superclass(Foo) == Class
@test_throws Exception superclass(AbstractFoo)


expected = """foo(obj::AbstractFoo) = begin
    obj.foo
end
set_foo!(obj::AbstractFoo, value::Int) = begin
    obj.foo = value
end
"""

output = @capture_out begin
    show_accessors(Foo)
end

function clean_str(s)
    s = replace(s, r"\n" => " ")
    s = replace(s, r"\s\s+" => " ")
end

@test clean_str(expected) == clean_str(output)

@class mutable Bar <: Foo begin
    bar::Int

    # Mutable classes can use this pattern
    function Bar(self::Union{Nothing, absclass(Bar)}=nothing)
        self = (self === nothing ? new() : self)
        superclass(Bar)(self)
        Bar(self, 0)
    end
end

@class Baz(mutable=true) <: Bar begin
   baz::Int

   function Baz(self::Union{Nothing, absclass(Baz)}=nothing)
        self = (self === nothing ? new() : self)
        superclass(Baz)(self)
        Baz(self, 0)
    end
end

# emitted by class Foo
# @method foo(obj::Foo) = obj.foo

@method function sum(obj::Bar)
    return foo(obj) + get_bar(obj)
end

@test Set(superclasses(Baz)) == Set([Foo, Bar, Class])
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

@test sum(y) == 21
@test get_bar(y) == 11
@test get_bar(z) == 101

@test_throws Exception get_bar(x)

# Mutable
set_foo!(z, 1000)
@test foo(z) == 1000

# Immutable
@test_throws Exception x.foo = 1000

# test that where clause is amended properly
@method zzz(obj::Foo, bar::T) where {T} = T

@test zzz(x, :x) == Symbol
@test zzz(y, 10.6) == Float64

# Test the corner case of conflicting mutability declarations.
# The eval(parse(string)) form is necessary; otherwise the error is raised
# when the macro is expanded, before @test_throws can catch it. Better way?
@test_throws(LoadError, eval(Meta.parse("@class mutable X1(mutable=false)")))

# Test other @class structural errors
@test_throws(LoadError, eval(Meta.parse("@class X2 x y")))
@test_throws(LoadError, eval(Meta.parse("@class (:junk,)")))

#
# Test generation of custom accessors
#
@class Buzz(setter_prefix="SET_", getter_prefix="GET_") begin
  s::Symbol
end

@test hasmethod(SET_s!, (AbstractBuzz, Symbol))
@test hasmethod(GET_s,  (Buzz,))

# Verify that default method doesn't exist
b = Buzz(:x)
@test_throws UndefVarError get_s(b)

# Test suppressing setters and getter prefix
@class Blub(setters=false, getter_prefix="") begin
    my_integer::Int
    my_float::Float64
end

b = Blub(10, 20.)

@test my_integer(b) == 10

@test_throws UndefVarError set_i!(b, 0)

struct NotAllowed <: AbstractFoo end

@test_throws Exception classof(AbstractFoo)

expected = """foo(obj::AbstractFoo) = begin
    obj.foo
end
set_foo!(obj::AbstractFoo, value::Int) = begin
    obj.foo = value
end
get_bar(obj::AbstractBar) = begin
    obj.bar
end
set_bar!(obj::AbstractBar, value::Int) = begin
    obj.bar = value
end
get_baz(obj::AbstractBaz) = begin
    obj.baz
end
set_baz!(obj::AbstractBaz, value::Int) = begin
    obj.baz = value
end
GET_s(obj::AbstractBuzz) = begin
    obj.s
end
SET_s!(obj::AbstractBuzz, value::Symbol) = begin
    obj.s = value
end
my_integer(obj::AbstractBlub) = begin
    obj.my_integer
end
my_float(obj::AbstractBlub) = begin
    obj.my_float
end
"""

output = @capture_out begin
    show_all_accessors()
end

function clean_str(s)
    s = replace(s, r"\n" => " ")
    s = replace(s, r"\s\s+" => " ")
end

@test clean_str(expected) == clean_str(output)

# Test initializer
Baz(z, 111)
@test z.baz == 111

@class NoAccessors(getters=false, setters=false) begin
  a::Int
  b::Int
end

n = NoAccessors(10, 11)

acc = Classes._accessors(:NoAccessors)

@test length(acc) == 0

# Test that parameterized type is handled properly
@class TupleHolder(getters=false, setters=false){NT <: NamedTuple} begin
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

upd = Baz(555, bar)
@test upd.foo == 1 && upd.bar == 2 && upd.baz == 555

# Test method structure
# "First argument of method whatever must be explicitly typed"
@test_throws(LoadError, eval(Meta.parse("@method whatever(i) = i")))
