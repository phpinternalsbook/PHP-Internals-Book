References
==========

PHP references (in the sense of the ``&`` symbol) are mostly transparent to userland code, but require consistent
special handling in the implementation. This chapter discusses how references are represented, and how internal code
should deal with them.

Reference semantics
-------------------

Before going into the internal representation of PHP references, it may be helpful to clarify some common
misconceptions about the semantics of references in PHP. Consider this basic example:

.. code-block:: php

    $a = 0;
    $b =& $a;
    $a++;
    $b++;
    var_dump($a); // int(2)
    var_dump($b); // int(2)

People will commonly say that "``$b`` is a reference to ``$a``". However, this is not quite correct, in that
references in PHP have no concept of directionality. After ``$b =& $a``, both ``$a`` and ``$b`` reference a common
value, and neither of the variables is privileged in any way.

This becomes particularly problematic when we consider the interaction of references and array copies:

.. code-block:: php

    $array = [0];
    $ref =& $array[0];
    $array2 = $array;
    $array2[] = 42; // Triggering copy-on-write makes no difference here.
    $ref++;
    var_dump($array[0]); // int(1)
    var_dump($array2[0]); // int(1)

The ``$ref =& $array[0]`` line creates a reference between ``$ref`` and ``$array[0]``. When the array is subsequently
copied, it becomes a reference between ``$ref``, ``$array[0]`` and ``$array2[0]``, as the reference is also copied.

Intuitively this behavior is wrong. There's two reasons why it happens: The first one is the aforementioned lack
of directionality. This behavior *would* make sense if we had written ``$array[0] =& $ref``. In this case it would be
expected that a copy of ``$array2[0]`` also points to ``$ref``. However, we cannot actually distinguish these two
cases.

The second and more important reason is a more technical one: ``$array2 = $array`` only performs a refcount increment,
which means we wouldn't have a chance to drop the reference even if we wanted to.

Representation
--------------

References are represented using an ``IS_REFERENCE`` zval that points to a ``zend_reference`` structure::

    struct _zend_reference {
        zend_refcounted_h              gc;
        zval                           val;
        zend_property_info_source_list sources;
    };

Zvals themselves do not have a reference count, and cannot be shared. The ``zend_reference`` structure essentially
represents a reference-counted zval that *can* be shared. Multiple zvals can point to the same ``zend_reference``,
and any change to the ``val`` it contains will be observable from all sources.

Type sources
~~~~~~~~~~~~

Normally, PHP does not track who or what makes use of a given reference. The only knowledge that is stored is how many
users there are (through the refcount), so that the reference may be destroyed in time.

However, due to the introduction of typed properties in PHP 7.4, we do need to track of which typed properties make
use of a certain reference, in order to enforce property types for indirect modifications through references:

.. code-block:: php

    class Test {
        public int $prop = 42;
    }
    $test = new Test;
    $ref =& $test->prop;
    $ref = "string"; // TypeError

The ``sources`` member of ``zend_reference`` stores a list of ``zend_property_info`` pointers to track typed properties
that use the reference. Macros like ``ZEND_REF_HAS_TYPE_SOURCES()``, ``ZEND_REF_ADD_TYPE_SOURCE()``, and
``ZEND_REF_DEL_TYPE_SOURCE()`` are used to manage this source list, but typically only engine code needs to deal with
this.

Initializing references
-----------------------

Just like other zvals, references are initialized through a set of macros. The most basic one accepts an already
created ``zend_reference`` pointer::

    zval ref;
    ZVAL_REF(ref, zend_reference_ptr);

To create a reference from scratch, ``ZVAL_NEW_REF()`` can be used::

    zval ref;
    zval initial_val;
    ZVAL_STRING(initial_val, "test");
    ZVAL_NEW_REF(&ref, &initial_val);

This macro accepts an initial value for the reference. Note that it is *moved* into the reference using
``ZVAL_COPY_VALUE``, the refcount is not incremented. Alternatively, ``ZVAL_NEW_EMPTY_REF()`` leaves the value
uninitialized::

    zval ref;
    ZVAL_NEW_EMPTY_REF(&ref);
    ZVAL_STRING(Z_REFVAL(ref), "test");

Here we create an empty reference and then initialize the reference value ``Z_REFVAL(ref)`` directly. Finally,
``ZVAL_MAKE_REF()`` can be used to promote an existing zval into a reference::

    zval *zv = /* ... */;
    ZVAL_MAKE_REF(zv);

If ``zv`` was already a reference, this does nothing. It if wasn't a reference yet, this will change ``zv`` into a
reference and set its initial value to the old value of ``zv``.

Dereferencing and unwrapping
----------------------------

Most code does not want to handle references in any special way, and simply want to look through to the underlying
value::

    zval *zv = /* ... */;
    if (Z_ISREF_P(zv)) {
        zv = Z_REFVAL_P(zv);
    }

If the value is a reference (``Z_ISREF``), we switch to looking at the value it contains. This operation is called
"dereferencing" and is more compactly written as ``ZVAL_DEREF(zv)``. It is extremely common and should be applied
essentially at any point where reference zvals might occur. For example, this is how a typical loop over an array
might look like::

    zval *val;
    ZEND_HASH_FOREACH_VAL(ht, val) {
        ZVAL_DEREF(val);

        /* Do something with val, now a guaranteed non-reference. */
    } ZEND_HASH_FOREACH_END();

The ``ZVAL_COPY_DEREF(target, source)`` macro is a combined form of ``ZVAL_COPY`` and ``ZVAL_DEREF``. It copies the
dereferenced value of ``source`` into ``target``.

Dereferencing simply moves a pointer from the outer to the inner zval, without changing either. It is also possible
to actually remove the reference wrapper by performing an unwrap. It is probably easiest to understand this operation
by looking at its implementation::

    static zend_always_inline void zend_unwrap_reference(zval *op) {
        if (Z_REFCOUNT_P(op) == 1) {
            ZVAL_UNREF(op);
        } else {
            Z_DELREF_P(op);
            ZVAL_COPY(op, Z_REFVAL_P(op));
        }
    }

If the refcount is 1, then the inner value is moved into ``op`` and the reference wrapper is destroyed. This is what
``ZVAL_UNREF()`` does. If the refcount is greater than one, then we decrement the refcount of the reference wrapper,
and copy (with refcount increase) the inner value into ``op``. This means that an unwrap operation does not necessarily
destroy the reference (if it has other users), but will remove one particular use.

Indirect zvals
--------------

Next to references, PHP also has a more direct mechanism to share zvals. The ``IS_INDIRECT`` type stores a direct
pointer to another zval::

    zval val1;
    ZVAL_LONG(&val1, 42);

    zval val2;
    ZVAL_INDIRECT(&val2, &val1);

    ZEND_ASSERT(Z_INDIRECT(val2) == &val1);

While there is some surface similarity to references, this mechanism is not generally usable, because nothing ensures
that the pointed-to zval isn't deallocated. For this reason, indirect zvals can only be used in controlled situations,
for example to point from a property hash table to a property slot table. This is possible, because we know that the
property slot table is not reallocated during the lifetime of an object, and the property hash table and property slot
table are deallocated at the same time, so no dangling pointers are left behind.

As such, indirect zvals can only occur in specific situations, and cannot be stored in general-purpose userland-exposed
zvals.
