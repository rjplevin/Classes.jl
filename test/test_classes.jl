using Classes

@class Foo(getter_prefix="") <: Class begin
   foo::Int

   Foo() = Foo(0)

   # Although Foo is immutable, subclasses might not be,
   # so it's still useful to define this method.
   function Foo(self::absclass(Foo))
        self.foo = 0
    end
end

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
@test_throws(LoadError, eval(Meta.parse("@class mutable XX(mutable=false)")))

#
# Test generation of custom accessors
#
@class Buzz(setter_prefix="SET_", getter_prefix="GET_") begin
  s::Symbol
end

@test hasmethod(SET_s!, (_Buzz_, Symbol))
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
