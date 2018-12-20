module Classes

using DataStructures
using MacroTools
using InteractiveUtils: subtypes

export @class, @method, Class, AbstractClass, classof, superclass, superclasses, issubclass, subclasses, 
    absclass, class_info, show_accessors, show_all_accessors

# Default values for meta-args to @class to control what the macro emits
_default_meta_args = Dict(
    :mutable => false,
    :getters => true,
    :setters => true,
    :getter_prefix => "get_",
    :getter_suffix => "",
    :setter_prefix => "set_",
    :setter_suffix => "!"
)

abstract type AbstractClass end            # supertype of all shadow class types
abstract type Class <: AbstractClass end   # superclass of all concrete classes

mutable struct ClassInfo
    name::Symbol
    class_module::Union{Nothing, Module}
    super::Union{Nothing, Symbol}
    ivars::Vector{Expr}
    meta_args::Dict{Symbol, Any}

    function ClassInfo(name::Symbol, super::Union{Nothing, Symbol}, ivars::Vector{Expr}, meta_args::Dict{Symbol, Any})
        new(name, nothing, super, ivars, meta_args)
    end
end

_classes = OrderedDict{Symbol, ClassInfo}(:Class => ClassInfo(:Class, nothing, Expr[], _default_meta_args))

function _register_class(name::Symbol, super::Symbol, ivars::Vector{Expr}, meta_args::Dict{Symbol, Any})
    _classes[name] = ClassInfo(name, super, ivars, meta_args)
end

_set_module!(info::ClassInfo, m::Module) = (info.class_module = m)

class_info(name::Symbol) = _classes[name]
class_info(::Type{T}) where {T <: AbstractClass} = class_info(nameof(T))

# Gets cumulative set of instance vars including those in all superclasses
function _all_ivars(cls::Symbol)
    info = class_info(cls)
    supercls = info.super
    parent_fields = (supercls === nothing ? [] : _all_ivars(supercls))
    return [parent_fields; info.ivars]
end

"""
    show_accessors(cls::Union{Symbol, AbstractClass})

Print the accessor functions emitted for the given class `cls`.
"""
function show_accessors(cls::Symbol)
    for def in _accessors(cls)
        println(MacroTools.striplines(def))
    end
end

show_accessors(::Type{T}) where {T <: AbstractClass} = show_accessors(nameof(T))

function show_all_accessors()
    for cls in keys(_classes)
        show_accessors(cls)
    end
end

"""
    superclass(t::Type{Class})

Returns the type of the concrete superclass of the given class, or `nothing`
for `Class`, which is the root of the class hierarchy.
"""
superclass(::Type{Class}) = nothing

"""
    superclasses(::Type{T}) where {T <: AbstractClass}

Returns a vector of superclasses from the superclass of the current class
to `Class`, in order.
"""
superclasses(::Type{Class}) = []

function superclasses(::Type{T}) where {T <: AbstractClass}
    super = superclass(T)
    [super, superclasses(super)...]
end

# catch-all
"""
    issubclass(t1::DataType, t2::DataType)

Returns `true` if `t1` is a subclass of `t2`, else false.
"""
# identity
issubclass(::Type{T}, ::Type{T}) where {T <: AbstractClass} = true

issubclass(::Type{T1}, ::Type{T2}) where {T1 <: AbstractClass, T2 <: AbstractClass} = T1 in Set(superclasses(T2))

"""
    classof(::Type{T}) where {T <: AbstractClass}

Compute the concrete class associated with a shadow abstract class, which must
be a subclass of AbstractClass.
"""
function classof(::Type{T}) where {T <: AbstractClass}
    if isconcretetype(T)
        return T
    end

    # Abstract types should have only one concrete subtype
    concrete = filter(isconcretetype, subtypes(T))

    if length(concrete) == 1
        return concrete[1]
    end

    # Should never happen unless user manually creates errant subtypes
    error("Abstract class supertype $T has multiple concrete subtypes: $concrete")
end

"""
    subclasses(::Type{T}) where {T <: AbstractClass}

Compute the vector of subclasses for a given class.
"""
function subclasses(::Type{T}) where {T <: AbstractClass}
    # immediate supertype is "our" entry in the type hierarchy
    super = supertype(T)
    
    # collect immediate subclasses
    subs = [classof(t) for t in subtypes(super) if isabstracttype(t)]

    # recurse on subclasses
    return [subs; [subclasses(t) for t in subs]...]
end

_absclass(cls::Symbol) = Symbol("Abstract$(cls)")

"""
    absclass(::Type{T}) where {T <: AbstractClass}

Returns the abstract type for the concrete class for `T`
"""
function absclass(::Type{T}) where {T <: AbstractClass}
    return isabstracttype(T) ? error("absclass(T) must be called on concrete classes. $T is abstract class type") : supertype(T)
end

_argnames(fields) = [sym for (sym, arg_type, slurp, default) in map(splitarg, fields)]

# We generate two initializer functions: one takes all fields, cumulative through superclasses,
# and another initializes only locally-defined fields. This function produces either, depending
# on the fields passed by _constructors().
function _initializer(class, fields, wheres)
    args = _argnames(fields)
    assigns = [:(self.$arg = $arg) for arg in args]

    funcdef = :(
        function $class(self::T, $(fields...)) where {T <: $(_absclass(class)), $(wheres...)}
            $(assigns...)
            self
        end
    )

    return funcdef
end

function _constructors(class, wheres)
    info = class_info(class)
    local_fields = info.ivars
    all_fields = _all_ivars(class)

    args = _argnames(all_fields)
    params = [clause.args[1] for clause in wheres]  # extract parameter names from where clauses

    dflt = length(params) > 0 ? :(
        function $class{$(params...)}($(all_fields...)) where {$(wheres...)}
            new{$(params...)}($(args...))
        end) : :(
        function $class($(all_fields...))
            new($(args...))
        end)
        
    init_all = _initializer(class, all_fields, wheres)
    methods = [dflt, init_all]

    # If class is a direct subclasses of Classes.Class, it has no fields
    # other than those defined locally, so the two methods would be identical.
    # In this case, we emit only one of them.
    if all_fields != local_fields
        init_local = _initializer(class, local_fields, wheres)
        push!(methods, init_local)
    end

    # Primarily for immutable classes, we emit a constructor that takes an instance
    # of the direct superclass and copies values when creating a new object.
    super_fields = _all_ivars(info.super)
    if length(super_fields) != 0
        super_args = [:(s.$arg) for arg in _argnames(super_fields)]
        local_args = _argnames(local_fields)
        all_args = [super_args; local_args]

        immut_init = length(params) > 0 ? :(
            function $class{$(params...)}($(local_fields...), s::$(info.super)) where {$(wheres...)}
                new{$(params...)}($(all_args...))
            end) : :(
            function $class($(local_fields...), s::$(info.super))
                new($(all_args...))
            end)
        push!(methods, immut_init)
    end

    return methods
end

# Generate "getter" and "setter" functions for all instance variables.
# For ivar `foo::T`, in class `ClassName`, generate:
#   get_foo(obj::absclass(ClassName)) = obj.foo
#   set_foo!(obj::absclass(ClassName), value::T) = (obj.foo = foo)
function _accessors(cls)
    exprs = Vector{Expr}()
    info = class_info(cls)

    meta_args = info.meta_args

    emit_getters = meta_args[:getters]
    emit_setters = meta_args[:setters]

    if ! (emit_getters || emit_setters)
        return exprs    # nothing to do
    end

    super = _absclass(cls)

    get_pre = meta_args[:getter_prefix]
    get_suf = meta_args[:getter_suffix]
    set_pre = meta_args[:setter_prefix]
    set_suf = meta_args[:setter_suffix]

    for (name, argtype, slurp, default) in map(splitarg, info.ivars)
        if emit_getters
            getter = Symbol("$(get_pre)$(name)$(get_suf)")
            push!(exprs, :($getter(obj::$super) = obj.$name))
        end

        if emit_setters
            setter = Symbol("$(set_pre)$(name)$(set_suf)")
            push!(exprs, :($setter(obj::$super, value::$argtype) = (obj.$name = value)))
        end
    end
    return exprs
end

function _parse_meta_args(cls, exprs, mutable)
    meta_args = copy(_default_meta_args)
    meta_args[:mutable] = mutable

    exprs === nothing && return meta_args
    
    for elt in exprs
        @capture(elt, name_ = value_) || error("@class $cls: Meta args must be a tuple of keyword assignments: got $exprs")
        haskey(meta_args, name)       || error("@class $cls: Unknown meta args name '$name'. Possible values are: $(Tuple(keys(_default_meta_args)))")
        
        # handle corner case of `@class mutable Foo(mutable=false)`
        if (mutable && name === :mutable && value == :false)
            error("Conflicting settings for 'mutable' in class $cls")
        end

        meta_args[name] = (value in (:true, :false) ? value == :true : value)   # avoid eval() to allow pre-compilation
    end

    return meta_args
end

macro class(elements...)
    # allow `@class mutable Foo` syntax
    if (mutable = (elements[1] == :mutable))
        elements = elements[2:end]
    end

    len = length(elements)
    if len == 1                       # no fields defined
        name_expr = elements[1]
        definition = quote end
    elseif len == 2
        (name_expr, definition) = elements
    else
        error("Unrecognized form for @class definition: $elements")
    end

    if ! @capture(definition, begin exprs__ end)
        error("@class $name_expr: badly formatted @class expression: $exprs")
    end
    
    # allow for optional type params and supertype
    if ! (@capture(name_expr, ((clsexpr_{wheres__}  | clsexpr_) <: supercls_) | (clsexpr_{wheres__} | clsexpr_)) &&
          (@capture(clsexpr, cls_(arglist__)) || @capture(clsexpr, cls_Symbol)))
        error("Unrecognized class name expression: `$name_expr`")
    end

    meta_args = _parse_meta_args(cls, arglist, mutable)
    mutable = meta_args[:mutable]   # in case it was specified in meta-args
    
    supercls = (supercls === nothing ? :Class : supercls)
    wheres   = (wheres === nothing ? [] : wheres)

    # split the expressions into constructors and field definitions
    ctors  = Vector{Expr}()
    fields = Vector{Expr}()
    for ex in exprs
        try 
            splitdef(ex)        # raises AssertionError if not a func def
            push!(ctors, ex)
        catch
            push!(fields, ex)
        end
    end

    info = _register_class(cls, supercls, fields, meta_args)

    all_fields = _all_ivars(cls) # including parents' fields, recursively

    abs_class = _absclass(cls)
    abs_super = _absclass(supercls)

    # add default constructors
    append!(ctors, _constructors(cls, wheres))

    struct_def = :(
        struct $cls{$(wheres...)} <: $abs_class
            $(all_fields...)
            $(ctors...)
        end
    )

    # toggles definition between mutable and immutable struct
    struct_def.args[1] = mutable

    accessors = _accessors(cls)

    result = quote
        abstract type $abs_class <: $abs_super end
        $struct_def
        $(accessors...)
        let info = class_info($cls)
            Classes._set_module!(info, @__MODULE__)
        end
        Classes.superclass(::Type{$cls}) = $supercls
        $cls    # return the struct type
    end

    return esc(result)
end

"""
    @method(funcdef)

Translates a function whose first argument is a concrete subclass of Class
the same function but with type of the first argument changed to the abstract
supertype of the class, thereby allowing it to be called on subclasses as well.
"""
macro method(funcdef)
    parts = splitdef(funcdef)
    name = parts[:name]
    args = parts[:args]
    whereparams = parts[:whereparams]

    if ! @capture(args[1], arg1_::T_)
        error("First argument of method $name must be explicitly typed")
    end

    type_symbol = gensym("T")  # gensym avoids conflict with user's type params
    abs_super = _absclass(T)

    # Redefine the function to accept any first arg that's a subclass of abstype
    parts[:whereparams] = (:($type_symbol <: $abs_super), whereparams...)
    args[1] = :($arg1::$type_symbol)
    expr = MacroTools.combinedef(parts)
    return esc(expr)
end

end # module
