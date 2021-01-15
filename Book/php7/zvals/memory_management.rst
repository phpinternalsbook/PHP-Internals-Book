Memory management 
=================

To work with zvals correctly and efficiently, it is important to understand how their memory management works. Broadly,
we can classify values into two categories: Simple values like integers, which are stored directly inside the zval, and
complex values like strings, for which the zval only stores a pointer to a separate structure.

.. _refcounting:

Reference-counted values
------------------------

All complex values share a common header with the following structure::

    typedef struct _zend_refcounted_h {
        uint32_t refcount;
        union {
            uint32_t type_info;
        } u;
    } zend_refcounted_h;

This header stores a reference count, which tracks in how many places this structure is used. If the structure is used
in a new zval, the refcount is incremented. If it stops being used, it is decremented. If the reference count reaches
zero, we know that the structure is no longer used and can be freed. This is the core mechanism of PHP's memory
management.

The ``type_info`` field encodes additional information, such as the type of the structure, a number of type-specific
flags, as well as a garbage collection root. We will discuss the purpose of this information later.

There are functions for creating different kinds of refcounted structures, which will create them with an initial
refcount of one::

    zend_string *str = zend_string_init("test", sizeof("test")-1, /* persistent */ 0); // refcount=1
    zend_array *arr = zend_new_array(/* size hint */ 0); // refcount=1

    // Do something with str and arr.

    zend_string_release(str); // refcount=0 => destroy!
    zend_array_release(arr); // refcount=0 => destroy!

The ``zend_string_release()`` and ``zend_array_release()`` functions will decrement the refcount of the string or array
and if it reaches zero, destroy it. For example, the following code is perfectly valid::

    zend_string *str = zend_string_init("test", sizeof("test")-1, /* persistent */ 0); // refcount=1
    zend_hash_add_empty_element(arr, str); // refcount=2
    zend_string_release(str); // refcount=1

This adds an element with key ``str`` to an array and releases the string afterwards. However, the
``zend_hash_add_empty_element()`` function will have incremented the refcount of the string, as such the
``zend_string_release()`` call will not destroy it. It will only get destroyed once the array is destroyed as well and
no references to the string remain.

Immutable values
~~~~~~~~~~~~~~~~

While all complex structures share the ``zend_refcounted_h`` header, the refcount is not always actually used. Strings
and arrays can be immutable, which means that that the entire structure, including the reference count, must never be
modified. Such structures can be reused without incrementing the reference count and are guaranteed to not be destroyed
until (at least) the end of the request.

There are a number of reasons why immutable strings and arrays exist:

  * Any structures stored in opcache shared memory are immutable, because they are shared across multiple processes.
    You can set the ``opcache.protect_memory=1`` ini setting in order to enforce this through ``mprotect()``. This will
    make most immutability violations result in crashes rather than misbehavior.
  * The empty array is declared ``const`` and as such typically allocated in a read-only segment. Attempting to modify
    it will result in a crash.
  * Persistent strings that are created outside a request but may be used inside it (such as ini values) must be
    immutable, because there may be multiple threads using them in parallel. As PHP's reference counting is non-atomic,
    performing normal refcounting would not be safe.
  * Finally, while the above reasons make immutable structures a technical requirement, having them also serves as a
    performance optimization, as refcounting operations can be avoided in many common cases.

When working with higher-level APIs such as ``zend_string_copy()`` or ``ZVAL_COPY()``, immutable structures will be
correctly handled automatically. However, if you use lower-level APIs, you need to take them into account explicitly.

The low-level interface is provided primarily through the following macros:

.. list-table::
    :header-rows: 1

    * - Macro
      - Description
    * - ``GC_TYPE``
      - Get type of the structure (``IS_*`` constant).
    * - ``GC_FLAGS``
      - Get flags.
    * - ``GC_REFCOUNT``
      - Get reference count.
    * - ``GC_ADDREF``
      - Increment refcount. Structure must be mutable.
    * - ``GC_DELREF``
      - Decrement refcount. Structure must be mutable. Does **not** release structure if refcount reaches zero.
    * - ``GC_TRY_ADDREF``
      - Increment refcount if mutable, otherwise do nothing.

Immutable structures set the ``GC_IMMUTABLE`` flag (which has a number of aliases like ``IS_STR_INTERNED`` and
``IS_ARRAY_IMMUTABLE``), which can be used to determine whether incrementing the refcount is safe::

    zend_string *str = /* ... */;

    if (!(GC_FLAGS(str) & GC_IMMUTABLE)) {
        GC_ADDREF(str);
    }

    // Same as:
    GC_TRY_ADDREF(str);

    // Same as (high-level API):
    zend_string_addref(str);

Macros that have ``TRY`` in the name generally indicate that an operation should only be performed for mutable
structures. You'll encounter more examples like ``Z_TRY_ADDREF`` and ``GC_TRY_PROTECT_RECURSION`` where the meaning is
the same.

Persistent structures
~~~~~~~~~~~~~~~~~~~~~

PHP makes use of two allocators: The per-request allocator, which releases all memory at the end of a request, and the
persistent allocator, which retains allocations across multiple requests. The persistent allocator is effectively
the same as the normal system allocator. See the :ref:`PHP Lifecycle <php_lifecycle>` and :ref:`zend_mm` chapters for
more information on PHP's allocation management.

Many functions that create refcounted structures will accept a ``persistent`` flag to determine which allocator to
use. An example of this is the last argument of ``zend_string_init()``. If a function exposes no ``persistent`` flag,
then a good default assumption is that the per-request (non-persistent) allocator is used. For example the
``zend_array_new()`` function always creates a per-request array, while lower-level APIs have to be used to create
a persistent array.

Persistent structures set the ``GC_PERSISTENT`` flag, and their destructors will automatically take care of using
the correct allocator to free the memory. As such, you generally do not need to worry about this flag beyond using the
correct allocator in the first place (usually the per-request one).

However, it is important to understand how persistent structures interact with code executed during a request:
Persistent structures can potentially be used by multiple threads. As PHP's reference counting is non-atomic,
performing refcounting from multiple threads results in a data race (that will result in crashes).

As such, any persistent structure that is also used during the request must either be immutable or thread-local.
PHP can be compiled using ``CFLAGS="-DZEND_RC_DEBUG=1"`` to diagnose such issues automatically. This problem most
typically affects strings, in which case they can be made immutable through interning. The
``GC_MAKE_PERSISTENT_LOCAL()`` macro is used to mark a persistent structure as thread-local. This macro doesn't do
anything beyond disabling the ``ZEND_RC_DEBUG`` verification.

Zval memory management
----------------------

With the preliminaries out of the way, we can discuss how memory management interacts with zvals. Refcounted
structures can be used independently, but storing them inside zvals is certainly one of the more common use-cases.

Zvals themselves are never individually heap-allocated. They are either allocated temporarily on the stack, or
embedded as part of a larger heap-allocated structure.

This basic example shows the initialization of a stack-allocated zval, and its subsequent destruction::

    zval str_val;
    ZVAL_STRING(&str_val, "foo"); // Creates zend_string (refcount=1).
    // ... Do something with str_val.
    zval_ptr_dtor(&str_val); // Decrements to refcount=0, and destroys the string.

``ZVAL_STRING()`` creates a string zval and ``zval_ptr_dtor()`` releases it. We'll discuss different initialization
macros and destructors in a moment.

A stack-allocated zval can only be used in the scope it was declared in. While it is technically possible to return
a ``zval``, you will find that PHP *never* passes or returns zvals by value. Instead zvals are always passed by
pointer. In order to return a zval, an out-parameter needs to be passed to the function::

    // retval is an output parameter.
    void init_zval(zval *retval) {
        ZVAL_STRING(retval, "foo");
    }

    void some_other_function() {
        zval val;
        init_zval(&val);
        // ... Do something with val.
        zval_ptr_dtor(&val);
    }

While zvals themselves are generally not shared, it's possible to share the structures they point to using the
refcounting mechanism. The ``Z_REFCOUNT``, ``Z_ADDREF`` and ``Z_DELREF`` macros work the same way as the
corresponding ``GC_*`` macros, but operate on zvals. Importantly, these macros can only be used if the zval does
point to a refcounted structure, and the structure is not immutable. Whether this is the case is stored in the
zval type flags as ``IS_TYPE_REFCOUNTED`` and can be accessed through ``Z_REFCOUNTED``::

    void fill_array(zval *array) {
        zval val;
        init_zval(&val);

        // Manually check REFCOUNTED:
        if (Z_REFCOUNTED(val)) {
            Z_ADDREF(val);
        }
        add_index_zval(array, 0, &val);

        // Or use the TRY macro:
        Z_TRY_ADDREF(val);
        add_index_zval(array, 1, &val);

        zval_ptr_dtor(&val);
    }

This example adds the same value to an array twice, which means the refcount has to be incremented twice. While it's
possible to manually check whether the zval is ``Z_REFCOUNTED``, it is preferred to use ``Z_TRY_ADDREF`` instead,
which only increments the refcount for refcounted structures.

Something to consider here is who is responsible for incrementing the refcount. In this example, the caller of
``add_index_zval()`` is responsible for the increment. Unfortunately, PHP APIs are not very consistent in this regard.
As a very rough rule of thumb, array values expect the refcount to be incremented by the caller, while most other
APIs will take care of it themselves.

Copying zvals
~~~~~~~~~~~~~

It is common that zvals need to be copied from one location to another. For this purpose, a number of copying macros
are provided. The first is ``ZVAL_COPY_VALUE()``::

    void init_zval_indirect(zval *retval) {
        zval val;
        init_zval(&val);
        ZVAL_COPY_VALUE(retval, &val);
    }

This (rather silly) example initializes a stack zval and then moves the value over into the ``retval`` out parameter.
The ``ZVAL_COPY_VALUE`` macro performs a simple zval copy without incrementing the refcount. As such, its primary
usage is to *move* a zval, which means that the original zval will no longer be used (which includes that it should
not be destroyed). Sometimes, this macro is also used as an optimization to *copy* a zval that we know not to be
refcounted.

The ``ZVAL_COPY_VALUE`` macro differs from a simple assignment (``*retval = val``) in that it only copies the zval
value and type, but not its u2 member. As such, it is safe to ``ZVAL_COPY_VALUE`` into a zval whose u2 member is
in used, as it will not be overwritten.

The second macro is ``ZVAL_COPY``, which is an optimized combination of ``ZVAL_COPY_VALUE`` and ``Z_TRY_ADDREF``::

    void init_pair(zval *retval1, zval *retval2) {
        zval val;
        init_zval(&val); // refcount=1

        ZVAL_COPY(retval1, &val); // refcount=2
        ZVAL_COPY(retval2, &val); // refcount=3

        zval_ptr_dtor(&val); // refcount=2
    }

This example copies the value twice, incrementing the refcount (if it has one) twice. A different, and slightly more
efficient way to write this function would be::

    void init_pair(zval *retval1, zval *retval2) {
        zval val;
        init_zval(&val); // refcount=1
        ZVAL_COPY(retval1, &val); // refcount=2
        ZVAL_COPY_VALUE(retval2, &val); // refcount=2
    }

This copies the value once into ``retval1``, and then performs a move into ``retval2``, saving a redundant refcount
increment and decrement. Finally, the way we would probably write this code in practice is this::

    void init_pair(zval *retval1, zval *retval2) {
        init_zval(retval1); // refcount=1
        ZVAL_COPY(retval2, retval1); // refcount=2
    }

Here, the value is directly initialized into ``retval1`` and then copied into ``retval2``. This version is both the
simplest and the most efficient.

The ``ZVAL_DUP`` macro is similar to ``ZVAL_COPY``, but will duplicate arrays, rather than just incrementing their
refcount. If you are using this macro, you are almost certainly doing something very wrong.

Finally, ``ZVAL_COPY_OR_DUP`` is a very specialized copy macro that can be used when copying from a potentially
persistent zval during the request. As mentioned before, incrementing the refcount is illegal in this case, because
it would not be thread-safe. This macro will increment the refcount on non-persistent values, but perform a full
string/array duplication for persistent values.

Destroying zvals
~~~~~~~~~~~~~~~~

The above examples have already been making use of ``zval_ptr_dtor()`` to destroy zvals. If the value is refcounted,
this function decrements the refcount and destroys the value when it reaches zero.

However, there is one subtlety here: Reference counting is not sufficient to detect unused values that are part
of cycles. For this reason, PHP employs an additional mark and sweep style circular garbage collector (GC). When the
refcount is decremented but does not reach zero, and the structure is marked as potentially circular (the
``GC_NOT_COLLECTABLE`` flag is not set), then PHP will add the structure to the GC root buffer.

The ``zval_ptr_dtor_nogc()`` function is a variant that does not perform GC root buffer checks, and is only safe to
use if you know that the destroyed data is non-circular. ``zval_dtor()`` is a legacy alias for the same function.

Another variant that can be encountered in internal code is ``i_zval_ptr_dtor()``, which is the same as
``zval_ptr_dtor()`` but using an inlined implementation. The ``i_`` prefix is a general convention for functions that
have both inlined and outlined variants.

.. _initializing_zvals:

Initializing zvals
~~~~~~~~~~~~~~~~~~

Until now, we have been using an abstract ``init_zval()`` function that *somehow* initializes a zval. It will not
come as a surprise that PHP handles zval initialization using a plethora of macros. The initialization of simple
types is especially straightforward::

    zval val;
    ZVAL_UNDEF(&val);

    zval val;
    ZVAL_NULL(&val);

    zval val;
    ZVAL_FALSE(&val);

    zval val;
    ZVAL_TRUE(&val);

    zval val;
    ZVAL_BOOL(&val, zero_or_one);

    zval val;
    ZVAL_LONG(&val, 42);

    zval val;
    ZVAL_DOUBLE(&val, 3.141);

For strings, there are quite a few initialization options. The most fundamental is the ``ZVAL_STR()`` macro, which
takes an already constructed ``zend_string*``::

    zval val;
    ZVAL_STR(&val, zend_string_init("test", sizeof("test")-1, 0));

As creating a ``zend_string`` from a string literal or an existing string is so common, there are two convenience
wrappers::

    zval val;
    ZVAL_STRINGL(&val, "test", sizeof("test")-1);

    zval val;
    ZVAL_STRING(&val, "test"); // Uses strlen() for length.

The ``ZVAL_STR`` macro will set the ``IS_TYPE_REFCOUNTED`` flag based on whether the string is immutable or not.
There are two optimized variants that can be known if it is known in advance whether the string is interned::

    // This string is definitely not interned/immutable.
    zval val;
    ZVAL_NEW_STR(&val, zend_string_init("test", sizeof("test")-1, 0));

    // This string is definitely interned.
    zval val;
    ZVAL_INTERNED_STR(&val, ZSTR_CHAR('a'));

Empty strings have a separate helper::

    zval val;
    ZVAL_EMPTY_STRING(&val);

The ``ZVAL_STRINGL_FAST`` macro can be used to avoid a ``zend_string`` allocation if the string is empty or has a
single character, as such strings always have interned variants that can be fetched quickly::

    zval val;
    ZVAL_STRINGL_FAST(&val, str, len);

Finally, the ``ZVAL_STR_COPY`` macro is a combination of ``ZVAL_STR`` and ``zend_string_copy``, where the latter
increments the refcount of the string::

    zval val;
    ZVAL_STR_COPY(&val, zstr); // Refcount will be incremented.
    // More efficient/compact version of:
    ZVAL_STR(&val, zend_string_copy(zstr));

For arrays, we thankfully only have to consider two initialization macros::

    zval val;
    ZVAL_ARR(&val, zend_new_array(/* size_hint */ 0));

    zval val;
    ZVAL_EMPTY_ARRAY(&val);

The first one initializes an array zval to an existing ``zend_array*`` structure, while the latter initializes an
empty array in particular. Note that while both of the above examples initialize an empty array, they are not the
same. ``ZVAL_EMPTY_ARRAY()`` uses an immutable shared empty array, while ``zend_new_array()`` creates a new one. If
you plan to modify the array directly afterwards, you should be using the ``zend_new_array()`` variant.

Object zvals are initialized using ``ZVAL_OBJ``::

    zval val;
    ZVAL_OBJ(&val, obj_ptr);

    zval val;
    ZVAL_OBJ_COPY(&val, obj_ptr); // Increments refcount

While these are somewhat common when dealing with already existing objects, ``object_init_ex()`` is the typical way
to create an object from scratch. This will covered in a later chapter on objects.

Finally, resources are initialized using ``ZVAL_RES``::

    zval val;
    ZVAL_RES(&val, zend_register_resource(ptr, le_resource_type));

Separating zvals
~~~~~~~~~~~~~~~~

In PHP, all values follow by-value semantics by default. This means that if you write ``$a = $b``, then modification
of ``$a`` will have no effect on ``$b`` and vice versa. At the same time, ``$a = $b`` is essentially implemented as::

    zval_ptr_dtor(a);
    ZVAL_COPY(a, b);

That is, ``$a`` and ``$b`` will both point to the same structure with an incremented refcount. This means that a
naive modification of ``$a`` would also modify ``$b``.

This is where the copy-on-write concept comes in: You are only permitted to modify structures that you exclusively
own, which means that they must have a refcount of one. If a structure has a refcount greater than one, it needs to
be *separated* first. Separation is just a fancy word for duplicating the structure.

In practice "structure" can be replaced with "array". While in theory the concept also applies to strings, strings
are almost never mutated after construction in PHP. As such ``SEPARATE_ARRAY()`` is the main separation macro, which
can only be applied to ``IS_ARRAY`` zvals::

    zval a, b;
    ZVAL_ARR(&b, zend_new_array(0));
    ZVAL_COPY(&a, &b);

    SEPARATE_ARRAY(&b); // b now holds a separate copy of the array.
    // Modification of b will no longer affect a.

The ``SEPARATE_ARRAY()`` macro takes care not only of shared arrays, but also of immutable ones::

    zval val;
    ZVAL_EMPTY_ARRAY(&val); // Immutable empty array.
    SEPARATE_ARRAY(&val); // Mutable copy of empty array.

The ``SEPARATE_ZVAL_NOREF()`` macro separates a generic zval, but is only rarely useful, as sepatation typically
directly precedes a modification, and you need to know the zval type to perform any meaningful modification anyway.

Objects and resources do not require separation, as they have reference-like semantics.
