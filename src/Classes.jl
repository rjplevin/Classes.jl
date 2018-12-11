module Classes

using MacroTools
using InteractiveUtils: subtypes

export @class, @method, classof, superclass, superclasses, issubclass, subclasses, absclass, class_info, Class, _Class_

# Default values for meta-options to @class
class_defaults = Dict(
    :mutable => false,
    :getters => true,
    :setters => true,
    :getter_prefix => "get_",
    :getter_suffix => "",
    :setter_prefix => "set_",
    :setter_suffix => "!"
)

abstract type _Class_ end            # supertype of all shadow class types
abstract type Class <: _Class_ end   # superclass of all concrete classes

struct ClassInfo
    name::Symbol
    # module::?
    super::Union{Nothing, Symbol}
    ismutable::Bool
    ivars::Vector{Expr}
end

_classes = Dict{Symbol, ClassInfo}(:Class => ClassInfo(:Class, nothing, false, []))

function _register_class(name, super, ismutable, ivars)
    _classes[name] = ClassInfo(name, super, ismutable, ivars)
end

class_info(name::Symbol) = _classes[name]
class_info(::Type{T}) where {T <: _Class_} = class_info(nameof(T))

# Gets cumulative set of instance vars including those in all superclasses
function _all_ivars(cls::Symbol)
    info = class_info(cls)
    supercls = info.super
    parent_fields = (supercls === nothing ? [] : _all_ivars(supercls))
    return [parent_fields; info.ivars]
end


# N.B. superclass() methods are emitted by @class macro
superclass(t::Type{Class}) = nothing

superclasses(t::Type{Class}) = []
superclasses(t::Type{T} where {T <: _Class_}) = [superclass(t), superclasses(superclass(t))...]

# catch-all
issubclass(t1::DataType, t2::DataType) = false

# identity
issubclass(t1::Type{T}, t2::Type{T}) where {T <: _Class_} = true

"""
    classof(::Type{T}) where {T <: _Class_}

Compute the concrete class associated with a shadow abstract class, which must
be a subclass of _Class_.
"""
function classof(::Type{T}) where {T <: _Class_}
    if ! isabstracttype(T)
        return T
    end

    # Abstract types should have only one concrete subtype
    concrete = filter(t -> !isabstracttype(t), subtypes(T))

    if length(concrete) == 1
        return concrete[1]
    end

    # Should never happen unless user manually creates errant subtypes
    error("Abstract class supertype $T has multiple concrete subtypes: $concrete")
end

"""
    subclasses(::Type{T}) where {T <: _Class_}

Compute the vector of subclasses for a given class.
"""
function subclasses(::Type{T}) where {T <: _Class_}
    # immediate supertype is "our" entry in the type hierarchy
    super = supertype(T)
    
    # collect immediate subclasses
    subs = [classof(t) for t in subtypes(super) if isabstracttype(t)]

    # recurse on subclasses
    return [subs; [subclasses(t) for t in subs]...]
end

"""
Return the symbol for the abstract class for `cls`
"""
_absclass(cls::Symbol) = Symbol("_$(cls)_")

function absclass(::Type{T}) where {T <: _Class_}
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
function _accessors(cls, meta_args)
    exprs = Vector{Expr}()

    emit_getters = meta_args[:getters]
    emit_setters = meta_args[:setters]

    if ! (emit_getters || emit_setters)
        return exprs    # nothing to do
    end

    info = class_info(cls)
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

function _parse_meta_args(elements)
    elt1 = elements[1]
    meta_args = copy(class_defaults)

    # allow simpler `@class mutable Name ...` syntax
    if elt1 == :mutable
        meta_args[:mutable] = true
        return (elements[2:end], meta_args)
    end
    
    if @capture(elt1, (exprs__,) | (name_ => value_))
        elements = elements[2:end]          # remove first element since we process it here

        if exprs === nothing
            exprs = (:($name => $value),)   # unified format for the loop that follows
        end

        for elt in exprs
            @capture(elt, name_ => value_) || error("@class meta variables must be a tuple of pairs: got $exprs")
            haskey(meta_args, name)        || error("Unknown @class meta variable name $name")

            meta_args[name] = (value in (:true, :false) ? eval(value) : value)
        end
    end

    return (elements, meta_args)
end

macro class(elements...)
    (elements, meta_args) = _parse_meta_args(elements)
    len = length(elements)
   
    if len == 1                       # no fields defined
        name_expr = elements[1]
        definition = quote end
    elseif len == 2
        (name_expr, definition) = elements
    else
        error("Unrecognized form for @class definition: $elements")
    end
   
    # @info "name: $name_expr"
    # @info "def: $definition"

    # Not required (@capture sets unmatched vars to nothing) but explicit 
    # assignment keeps the editor from complaining about undef'd vars.
    cls = supercls = wheres = exprs = nothing

    if ! @capture(definition, begin exprs__ end)
        error("@class $name_expr: badly formatted @class expression: $exprs")
    end
    
    # allow for optional type params and supertype
    if ! @capture(name_expr, ((cls_{wheres__}  | cls_) <: supercls_) | (cls_{wheres__} | cls_))
        error("Unrecognized class name expression: $name_expr")
    end

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

    mutable = meta_args[:mutable]
    _register_class(cls, supercls, mutable, fields)

    all_fields = _all_ivars(cls) # including parents' fields, recursively

    abs_class = _absclass(cls)
    abs_super = _absclass(supercls)

    # TBD: Modify this to add "local" constructor, calling parent if superclass(x) != Class

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

    accessors = _accessors(cls, meta_args)

    result = quote
        abstract type $abs_class <: $abs_super end
        $struct_def
        $(accessors...)

        Classes.superclass(::Type{$cls}) = $supercls
        Classes.issubclass(::Type{$cls}, ::Type{$supercls}) = true
    end

    # Start traversal up hierarchy with superclass since superclass() for 
    # this class doesn't exist until after this macro is evaluated.
    expr = quote
        for sup in superclasses($supercls)
            eval(:(Classes.issubclass(::Type{$$cls}, ::Type{$sup}) = true))
        end
        nothing
    end

    push!(result.args, expr)
    return esc(result)
end

#=
    @method get_foo(obj::MyClass) obj.foo
->
    get_foo(obj::T) where T <: _MyClass_
    
so it works on subclasses, too.
=#

macro method(funcdef)
    parts = splitdef(funcdef)
    name = parts[:name]
    args = parts[:args]
    whereparams = parts[:whereparams]

    if ! @capture(args[1], arg1_::T_)
        error("First argument of method $name must be explicitly typed")
    end

    type_symbol = gensym("$T")
    abs_super = _absclass(T)

    # Redefine the function to accept any first arg that's a subclass of abstype
    parts[:whereparams] = (:($type_symbol <: $abs_super), whereparams...)
    args[1] = :($arg1::$type_symbol)
    expr = MacroTools.combinedef(parts)
    return esc(expr)
end

end # module
