module Classes

using DataStructures
using MacroTools
using InteractiveUtils: subtypes

export @class, @method, Class, AbstractClass, isclass, classof, superclass, superclasses, issubclass, subclasses, absclass

abstract type AbstractClass end            # supertype of all shadow class types
abstract type Class <: AbstractClass end   # superclass of all concrete classes

abs_symbol(cls::Symbol) = Symbol("Abstract", cls)

# Return info about a class in a named tuple
function _class_info(::Type{T}) where {T <: AbstractClass}
    ivars = (isabstracttype(T) ? Expr[] : [:($vname::$vtype) for (vname, vtype) in zip(fieldnames(T), T.types)])
    return (modname=T.name.module, mutable=T.mutable, parameters=T.parameters, ivars=ivars, super=superclass(T))
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

"""
    isclass(X)

Return `true` if `X` is a concrete subclass of `AbstractClass`, or is `Class`, which is abstract.
"""
isclass(any) = false
isclass(::Type{T}) where {T <: AbstractClass} = (T === Class || isconcretetype(T))

"""
    issubclass(t1::DataType, t2::DataType)

Returns `true` if `t1` is a subclass of `t2`, else false.
"""
# identity
issubclass(::Type{T}, ::Type{T}) where {T <: AbstractClass} = true

issubclass(::Type{T1}, ::Type{T2}) where {T1 <: AbstractClass, T2 <: AbstractClass} = T1 in Set(superclasses(T2))

"""
    classof(::Type{T}) where {T <: AbstractClass}

Compute the concrete class associated with abstract class `T`, which must
be a subclass of `AbstractClass`.
"""
function classof(::Type{T}) where {T <: AbstractClass}
    if isclass(T)
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

"""
    absclass(::Type{T}) where {T <: AbstractClass}

Returns the abstract type associated with the concrete class `T`.
"""
function absclass(::Type{T}) where {T <: AbstractClass}
    isclass(T) ? supertype(T) : error("absclass(T) must be called on concrete classes; $T is abstract.")
end

function _argnames(fields)
    return [sym for (sym, arg_type, slurp, default) in map(splitarg, fields)]
end

# We generate two initializer functions: one takes all fields, cumulative through superclasses,
# and another initializes only locally-defined fields. This function produces either, depending
# on the fields passed by _constructors().
function _initializer(class, fields, wheres)
    args = _argnames(fields)
    assigns = [:(_self.$arg = $arg) for arg in args]

    funcdef = :(
        function $class(_self::T, $(fields...)) where {T <: $(abs_symbol(class)), $(wheres...)}
            $(assigns...)
            _self
        end
    )

    return funcdef
end

function _constructors(clsname, super, local_fields, all_fields, wheres)
    args = _argnames(all_fields)
    params = [clause.args[1] for clause in wheres]  # extract parameter names from where clauses

    dflt = length(params) > 0 ? :(
        function $clsname{$(params...)}($(all_fields...)) where {$(wheres...)}
            new{$(params...)}($(args...))
        end) : :(
        function $clsname($(all_fields...))
            new($(args...))
        end)
        
    init_all = _initializer(clsname, all_fields, wheres)
    methods = [dflt, init_all]

    # If clsname is a direct subclasses of Classes.Class, it has no fields
    # other than those defined locally, so the two methods would be identical.
    # In this case, we emit only one of them.
    if all_fields != local_fields
        init_local = _initializer(clsname, local_fields, wheres)
        push!(methods, init_local)
    end

    # Primarily for immutable classes, we emit a constructor that takes an instance
    # of the direct superclass and copies values when creating a new object.
    super_info = _class_info(super)
    super_fields = super_info.ivars
    if length(super_fields) != 0
        super_args = [:(_super.$arg) for arg in _argnames(super_fields)]
        local_args = _argnames(local_fields)
        all_args = [super_args; local_args]

        immut_init = length(params) > 0 ? :(
            function $clsname{$(params...)}(_super::$super, $(local_fields...)) where {$(wheres...)}
                new{$(params...)}($(all_args...))
            end) : :(
            function $clsname(_super::$super, $(local_fields...))
                new($(all_args...))
            end)
        push!(methods, immut_init)
    end

    return methods
end

function _defclass(clsname, supercls, mutable, wheres, exprs)   
    wheres   = (wheres === nothing ? [] : wheres)

    # partition expressions into constructors and field defs
    ctors  = Vector{Expr}()
    fields = Vector{Expr}()
    for ex in exprs
        try 
            splitdef(ex)        # throws AssertionError if not a func def
            push!(ctors, ex)
        catch
            push!(fields, ex)
        end
    end

    superinfo = _class_info(supercls)
    all_fields = copy(superinfo.ivars)
    append!(all_fields, fields)

    # add default constructors
    append!(ctors, _constructors(clsname, supercls, fields, all_fields, wheres))

    abs_class = abs_symbol(clsname)
    abs_super = absclass(supercls)

    struct_def = :(
        struct $clsname{$(wheres...)} <: $abs_class
            $(all_fields...)
            $(ctors...)
        end
    )

    # set mutability flag
    struct_def.args[1] = mutable

    result = quote
        abstract type $abs_class <: $abs_super end
        $struct_def

        Classes.superclass(::Type{$clsname}) = $supercls
        $clsname    # return the struct type
    end

    return result
end

macro class(elements...)
    if (mutable = (elements[1] == :mutable))
        elements = elements[2:end]
    end

    if (len = length(elements)) == 1                       # no fields defined
        name_expr = elements[1]
        definition = quote end
    elseif len == 2
        (name_expr, definition) = elements
    else
        error("Unrecognized form for @class definition: $elements")
    end

    # initialize the "captured" vars to avoid "unknown var" warnings
    cls = clsname = exprs = wheres = nothing

    @capture(definition, begin exprs__ end)
    
    # allow for optional type params and supertype
    if ! (@capture(name_expr, ((cls_{wheres__} | cls_) <: supername_) | (cls_{wheres__} | cls_)) && cls isa Symbol)
        error("Unrecognized class name expression: `$name_expr`")
    end

    # The explicit eval forces supername to be eval'd in calling environment
    supername = (supername === nothing ? :Class : supername)
    expr = :(eval(Classes._defclass($(QuoteNode(cls)), $supername, $mutable, $wheres, $exprs)))
    return esc(expr)
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
    abs_super = abs_symbol(T)

    # Redefine the function to accept any first arg that's a subclass of abstype
    parts[:whereparams] = (:($type_symbol <: $abs_super), whereparams...)
    args[1] = :($arg1::$type_symbol)
    expr = MacroTools.combinedef(parts)
    return esc(expr)
end

end # module
