Memory management
=================

The zval structure has two roles: The first, which was described in the previous section, is to store a value and its
type. The second, which will be covered in this section, is to efficiently manage those values in memory.

In the following we'll have a look at the concepts of reference-counting and copy-on-write and find out how to make use
of them in extension code.

Value- and reference-semantics
------------------------------

In PHP all values always have value-semantics, unless you explicitly ask for a reference. This means that whenever
you pass a value to a function or assign one variable to another you'll be working on two separate copies of the value.
Some examples to make sure that this is clear:

.. code-block:: php

    <?php

    $a = 1;
    $b = $a;
    $a++;

    // Only $a was incremented, $b stays as is:
    var_dump($a, $b); // int(2), int(1)

    function inc($n) {
        $n++;
    }

    $c = 1;
    inc($c);

    // The $c value outside the function and the $n inside the function are distinct
    var_dump($c); // int(1)

While the above is rather obvious, it's important to realize that this is a general rule that always holds. In
particular this also applies to objects:

.. code-block:: php

    <?php

    $obj = (object) ['value' => 1];

    function fnByVal($val) {
        $val = 100;
    }

    function fnByRef(&$ref) {
        $ref = 100;
    }

    // The by-value function does not modify $obj, the by-reference function does:

    fnByVal($obj);
    var_dump($obj); // stdClass(value => 1)
    fnByRef($obj);
    var_dump($obj); // int(100)

People often say that objects are automatically passed by-reference since PHP 5, but as the above example shows this is
not true: A by-value function cannot modify the value of the variable that was passed to it, only a by-reference
function can do that.

It is true however that objects exhibit a "reference-like" behavior: While you can not assign a completely different
value, you can still change the properties of the object. This is a result of the fact than an object value is just an
ID that can be used to look up the "actual content" of the object. Value-semantics only prevent you from changing this
ID to a different object or switching the type altogether, but they do not prevent you to change the "actual content" of
the object.

The same applies to resources, because they also only store an ID which can be used up to look up their actual value.
So again the value-semantics prevent you from changing the resource ID or the type of the zval, but they do not
prevent you from changing the content of the resource (like advancing the position in a file).

Reference-counting and copy-on-write
------------------------------------

If you think about the above for a bit, you'll come to the conclusion that PHP must be doing an awful lot of copying.
Every time you pass something to a function the value needs to be copied. This may not be particularly problematic for
an integer or a double, but imagine passing an array with ten million elements to a function. Copying millions of
elements on every call would be prohibitively slow.

To avoid doing so PHP employs the copy-on-write paradigm: A zval can be shared by multiple variables/functions/etc as
long as it's only read from and not modified. If one of the holders wants to modify it, the zval needs to be copied
before applying any changes.

If one zval can be used in multiple places, PHP needs some way to find out when the zval is no longer used by anyone
in order to destroy (and free) it. PHP accomplishes this simply by keeping track of how often the zval is referenced.
Note that "referenced" here has nothing to do with PHP references (as in ``&``) and just means that something (a
variable, function, etc) makes use of the zval. The number of references is called the *refcount* and stored in the
``refcount__gc`` member of the zval.

To understand how this works lets consider an example:

.. code-block:: php

    <?php

    $a = 1;    // $a =           zval_1(value=1, refcount=1)
    $b = $a;   // $a = $b =      zval_1(value=1, refcount=2)
    $c = $b;   // $a = $b = $c = zval_1(value=1, refcount=3)

    $a++;      // $b = $c = zval_1(value=1, refcount=2)
               // $a =      zval_2(value=2, refcount=1)

    unset($b); // $c = zval_1(value=1, refcount=1)
               // $a = zval_2(value=2, refcount=1)

    unset($c); // zval_1 is destroyed, because refcount=0
               // $a = zval_2(value=2, refcount=1)

The behavior is very straightforward: When a reference is added, increment the refcount, if a reference is removed,
decrement it. If the refcount reaches 0 the zval is destroyed.

One case where this method does not work is in case of a circular reference:

.. code-block:: php

    <?php

    $a = []; // $a = zval_1(value=[], refcount=1)
    $b = []; // $b = zval_2(value=[], refcount=1)

    $a[0] = $b; // $a = zval_1(value=[0 => zval_2], refcount=1)
                // $b = zval_2(value=[], refcount=2)
                // The refcount of zval_2 is incremented because it
                // is used in the array of zval_1

    $b[0] = $a; // $a = zval_1(value=[0 => zval_2], refcount=2)
                // $b = zval_2(value=[0 => zval_1], refcount=2)
                // The refcount of zval_1 is incremented because it
                // is used in the array of zval_2

    unset($a);  //      zval_1(value=[0 => zval_2], refcount=1)
                // $b = zval_2(value=[0 => zval_1], refcount=2)
                // The refcount of zval_1 is decremented, but the zval has
                // to stay alive because it's still referenced by zval_2

    unset($b);  //      zval_1(value=[0 => zval_2], refcount=1)
                //      zval_2(value=[0 => zval_1], refcount=1)
                // The refcount of zval_2 is decremented, but the zval has
                // to stay alive because it's still referenced by zval_1

After the above code has run we have reached a situation where we have two zvals that are not reachable by any variable,
but are still kept alive because they reference each other. This is a classical example of where reference-counting
fails.

To address this issue PHP has a second garbage collection mechanism. How this cycle collector works will be covered in
[TODO:ref]. We can safely ignore it for now, because the cycle collector (unlike the reference-counting mechanism) is
mostly transparent to extension authors.

Another case that has to be considered are "actual" PHP references (as in ``&$var``, not the internal "references" we've
been talking about above). To denote that a zval uses a PHP reference a boolean is_ref flag is used, which is stored in
the ``is_ref__gc`` member of the zval structure.

An ``is_ref=1`` flag on a zval signals that the zval should **not** be copied before modification. Instead code should
directly modify the value:

.. code-block:: php

    <?php

    $a = 1;   // $a =      zval_1(value=1, refcount=1, is_ref=0)
    $b =& $a; // $a = $b = zval_1(value=1, refcount=2, is_ref=1)

    $b++;     // $a = $b = zval_1(value=2, refcount=2, is_ref=1)
              // Due to the is_ref=1 PHP directly changes the zval
              // rather than making a copy

In the above example the zval of ``$a`` has refcount=1 before the reference is created. Now consider a very similar
example where the original refcount is larger than one:

.. code-block:: php

    <?php

    $a = 1;   // $a =           zval_1(value=1, refcount=1, is_ref=0)
    $b = $a;  // $a = $b =      zval_1(value=1, refcount=2, is_ref=0)
    $c = $b   // $a = $b = $c = zval_1(value=1, refcount=3, is_ref=0)

    $d =& $c; // $a = $b = zval_1(value=1, refcount=2, is_ref=0)
              // $c = $d = zval_2(value=1, refcount=2, is_ref=1)
              // $d is a reference of $c, but *not* of $a and $b, so
              // the zval needs to be copied here. Now we have the
              // same zval once with is_ref=0 and once with is_ref=1.

    $d++;     // $a = $b = zval_1(value=1, refcount=2, is_ref=0)
              // $c = $d = zval_2(value=2, refcount=2, is_ref=1)
              // Because there are two separate zvals $d++ does
              // not modify $a and $b (as expected).

As you can see ``&``-referencing a zval with is_ref=0 and refcount>1 requires a copy. Similarly trying to use a zval
with is_ref=1 and refcount>1 in a by-value context will require a copy. For this reason making use of PHP references
usually slows code down: Nearly all functions in PHP use by-value passing semantics, so they will likely trigger a copy
when an is_ref=1 zval is passed to them.

Allocating and initializing zvals
---------------------------------

Now that you are familiar with the general concepts underlying zval memory management, we can move on to their practical
implementation. Lets start with zval allocation::

    zval *zv_ptr;
    ALLOC_ZVAL(zv_ptr);

This code-snippets allocates a zval, but does not initialize its members. There is a variant of this macro used to
allocate persistent zvals, which are not destroyed at the end of the request::

    zval *zv_ptr;
    ALLOC_PERMANENT_ZVAL(zv_ptr);

The difference between the two macros is that the former makes use of ``emalloc()`` whereas the latter uses
``malloc()``. It's important to know though that trying to directly allocate zvals will not work::

    /* This code is WRONG */
    zval *zv_ptr = emalloc(sizeof(zval));

The reason is that the cycle collector needs to store some additional information in the zval, so the structure that
needs to be allocated is actually not a ``zval`` but a ``zval_gc_info``::

    typedef struct _zval_gc_info {
        zval z;
        union {
            gc_root_buffer       *buffered;
            struct _zval_gc_info *next;
        } u;
    } zval_gc_info;

The ``ALLOC_*`` macros will allocate a ``zval_gc_info`` and initialize its additional member, but afterwards the value
can be transparently used as a ``zval`` (because the structure includes a ``zval`` as its first member).

After the zval has been allocated it needs to be initialized. There are two macros do to this. The first one is
``INIT_PZVAL``, which will set refcount=1 and is_ref=0 but leave the value uninitialized::

    zval *zv_ptr;
    ALLOC_ZVAL(zv_ptr);
    INIT_PZVAL(zv_ptr);
    /* zv_ptr has garbage type+value here */

The second macro is ``INIT_ZVAL`` which will also set refcount=1 and is_ref=0, but will additionally set the type to
``IS_NULL``::

    zval *zv_ptr;
    ALLOC_ZVAL(zv_ptr);
    INIT_ZVAL(*zv_ptr);
    /* zv_ptr has type=IS_NULL here */

``INIT_PZVAL()`` accepts a ``zval*`` (thus the ``P`` in its name) whereas ``INIT_ZVAL()`` takes a ``zval``. When passing
a ``zval*`` to the latter macro it needs to be dereferenced first.

Because it is very common to both allocate and initialize a zval in one go there are two macros which combine both
steps::

    zval *zv_ptr;
    MAKE_STD_ZVAL(zv_ptr);
    /* zv_ptr has garbage type+value here */

    zval *zv_ptr;
    ALLOC_INIT_ZVAL(zv_ptr);
    /* zv_ptr has type=IS_NULL here */

``MAKE_STD_ZVAL()`` combines allocation with ``INIT_PZVAL()``, whereas ``ALLOC_INIT_ZVAL()`` combines it with
``INIT_ZVAL()``.

Managing the refcount and zval destruction
------------------------------------------

Once you have an allocated and initialized zval you can make use of the reference-counting mechanism introduced earlier.
To manage the refcount PHP provides several macros::

    Z_REFCOUNT_P(zv_ptr)      /* Get refcount */
    Z_ADDREF_P(zv_ptr)        /* Increment refcount */
    Z_DELREF_P(zv_ptr)        /* Decrement refcount */
    Z_SET_REFCOUNT(zv_ptr, 1) /* Set refcount to some particular value (here 1) */

Just like the other ``Z_`` macros these are available in variants without a suffix, with a ``_P`` suffix and with a
``_PP`` suffix, which accept a ``zval``, a ``zval*`` and a ``zval**`` respectively.

The macro you will most commonly use is ``Z_ADDREF_P()``. A small example::

    zval *zv_ptr;
    MAKE_STD_ZVAL(zv_ptr);
    ZVAL_LONG(zv_ptr, 42);

    add_index_zval(some_array, 0, zv_ptr);
    add_assoc_zval(some_array, "num", zv_ptr);
    Z_ADDREF_P(zv_ptr);

The code inserts the integer 42 into an array at the index ``0`` and the key ``"num"``, so the zval will be used in two
places. After the allocation and initialization done by ``MAKE_STD_ZVAL()`` the zval starts off with a refcount of 1.
To use the same zval in two places it needs a refcount of 2, thus it has to be incremented using ``Z_ADDREF_P()``.

The complement macro ``Z_DELREF_P()`` on the other hand is used rather rarely: Usually just decrementing the refcount
is not enough, because you have to check for the ``refcount==0`` case where the zval needs to be destroyed and freed::

    Z_DELREF_P(zv_ptr);
    if (Z_REFCOUNT_P(zv_ptr) == 0) {
        zval_dtor(zv_ptr);
        efree(zv_ptr);
    }

The ``zval_dtor()`` macro takes a ``zval*`` and destroys its value: If it is a string, the string will be freed, if it
is an array, the HashTable will be destroyed and freed, if it is an object or resource, the refcount of their actual
values is decremented (which again might lead to them being destroyed and freed).

Instead of writing the above code for checking the refcount yourself, you should use a second macro called
``zval_ptr_dtor()``::

    zval_ptr_dtor(&zv_ptr);

This macro takes a ``zval**`` (for historical reasons, it could take a ``zval*`` just as well), decrements its refcount
and checks whether the zval needs to be destroyed and freed. But unlike our manually written code above it also includes
support for the collection of circles. Here is the relevant part of its implementation::

    static zend_always_inline void i_zval_ptr_dtor(zval *zval_ptr ZEND_FILE_LINE_DC TSRMLS_DC)
    {
        if (!Z_DELREF_P(zval_ptr)) {
            ZEND_ASSERT(zval_ptr != &EG(uninitialized_zval));
            GC_REMOVE_ZVAL_FROM_BUFFER(zval_ptr);
            zval_dtor(zval_ptr);
            efree_rel(zval_ptr);
        } else {
            if (Z_REFCOUNT_P(zval_ptr) == 1) {
                Z_UNSET_ISREF_P(zval_ptr);
            }

            GC_ZVAL_CHECK_POSSIBLE_ROOT(zval_ptr);
        }
    }

``Z_DELREF_P()`` returns the new refcount after it was decremented, so writing ``!Z_DELREF_P(zval_ptr)`` is the same
as writing ``Z_DELREF_P(zval_ptr)`` followed by a check for ``Z_REFCOUNT_P(zval_ptr) == 0``.

Apart from doing the expected ``zval_dtor()`` and ``efree()`` operations the code also calls two ``GC_*`` macros
handling cycle collection and asserts that ``&EG(uninitialized_zval)`` is never freed (this is a magic zval used by the
engine).

Furthermore the code also sets ``is_ref=0`` if there is only one reference left to the zval. Leaving ``is_ref=1`` in
this case wouldn't really make sense because the concept of a ``&`` PHP reference only becomes meaningful when two or
more holders share a zval.

Some hints on the usage of these macros: You should not use ``Z_DELREF_P()`` at all (it's only applicable in situations
where you can guarantee that the zval neither needs to be destroyed nor is a possible root for a circle). Instead you
should use ``zval_ptr_dtor()`` whenever you want to decrement the refcount. The ``zval_dtor()`` macro is typically used
with temporary, stack-allocated zvals::

    zval zv;
    INIT_ZVAL(zv);

    /* Do something with zv here */

    zval_dtor(&zv);

A temporary zval allocated on the stack cannot be shared because it is freed at the end of the block, as such it cannot
make use of refcounting and can be destroyed indiscriminately using ``zval_dtor()``.

Copying zvals
-------------

While the copy-on-write mechanism can save a lot of zval copies, they do have to happen at some point, e.g. if you
want to change the value of the zval or transfer it to another storage location.

PHP provides a large number of copying macros for various use cases, the simplest one being ``ZVAL_COPY_VALUE()``,
which just copies the ``value`` and ``type`` members of a zval::

    zval *zv_src;
    MAKE_STD_ZVAL(zv_src);
    ZVAL_STRING(zv_src, "test", 1);

    zval *zv_dest;
    ALLOC_ZVAL(zv_dest);
    ZVAL_COPY_VALUE(zv_dest, zv_src);

At this point ``zv_dest`` will have the same type and value as ``zv_src``. Note that "same value" here means that both
zvals are using the same string value (``char*``), i.e. if the ``zv_src`` zval is destroyed the string value would be
freed and ``zv_dest`` would be left with a dangling pointer to the freed string. To avoid this the zval copy
constructor ``zval_copy_ctor()`` needs to be invoked::

    zval *zv_dest;
    ALLOC_ZVAL(zv_dest);
    ZVAL_COPY_VALUE(zv_dest, zv_src);
    zval_copy_ctor(zv_dest);

``zval_copy_ctor()`` will do a fully copy of the zval value, i.e. if it is a string the ``char*`` will be copied, if it
is an array the ``HashTable*`` is copied and if it is an object or resource their internal reference counts are
incremented.

The only thing that is missing now is the initialization of the refcount and the is_ref flag. This could be done using
the ``INIT_PZVAL()`` macro or by making use of ``MAKE_STD_ZVAL()`` instead of ``ALLOC_ZVAL()``. Another alternative is
to use ``INIT_PZVAL_COPY()`` instead of ``ZVAL_COPY_VALUE()`` which combines doing a copy with refcount/is_ref
initialization::

    zval *zv_dest;
    ALLOC_ZVAL(zv_dest);
    INIT_PZVAL_COPY(zv_dest, zv_src);
    zval_copy_ctor(zv_dest);

As the combination of ``INIT_PZVAL_COPY()`` and ``zval_copy_ctor()`` is very a common both are combined in the
``MAKE_COPY_ZVAL()`` macro::

    zval *zv_dest;
    ALLOC_ZVAL(zv_dest);
    MAKE_COPY_ZVAL(&zv_src, zv_dest);

This macro has a bit of a tricky signature, because it swaps the argument order (the destination is now the second
argument rather) and also requires the source to be a ``zval**``. Once again this is just a historic artifact and
doesn't make any technical sense whatsoever.

Apart from these basic copying macros there are several more complicated ones. The most important is ``ZVAL_ZVAL``,
which is especially common when returning zvals from a function. It has the following signature::

    ZVAL_ZVAL(zv_dest, zv_src, copy, dtor)

The ``copy`` parameter specifies whether ``zval_copy_ctor()`` should be called on the destination zval and ``dtor``
determines whether ``zval_ptr_dtor()`` is called on the source zval. Let's go through all four possible combinations
of those values and analyze the behavior. The simplest case is setting both copy and dtor to zero::

    ZVAL_ZVAL(zv_dest, zv_src, 0, 0);
    /* equivalent to: */
    ZVAL_COPY_VALUE(zv_dest, zv_src)

In this case ``ZVAL_ZVAL()`` becomes a simple ``ZVAL_COPY_VALUE()`` call. As such using this macro with 0,0 arguments
doesn't really make sense. A more useful variant is copy=1, dtor=0::

    ZVAL_ZVAL(zv_dest, zv_src, 1, 0);
    /* equivalent to: */
    ZVAL_COPY_VALUE(zv_dest, zv_src);
    zval_copy_ctor(&zv_src);

This is basically a normal zval copy analog to ``MAKE_COPY_ZVAL()``, only without the ``INIT_PZVAL()`` step. This is
useful when copying into zvals that are already initialized (e.g. ``return_value``). Additionally setting dtor=1 only
adds a ``zval_ptr_dtor()`` call::

    ZVAL_ZVAL(zv_dest, zv_src, 1, 1);
    /* equivalent to: */
    ZVAL_COPY_VALUE(zv_dest, zv_src);
    zval_copy_ctor(zv_dest);
    zval_ptr_dtor(&zv_src);

The most interesting case is the copy=0, dtor=1 combination::

    ZVAL_ZVAL(zv_dest, zv_src, 0, 1);
    /* equivalent to: */
    ZVAL_COPY_VALUE(zv_dest, zv_src);
    ZVAL_NULL(zv_src);
    zval_ptr_dtor(&zv_src);

This constitutes a zval move, where the value from ``zv_src`` is moved into ``zv_dest`` without having to invoke the
copy constructor. This is something that should only be done if ``zv_src`` has refcount=1, in which case the zval will
be destroyed by the ``zval_ptr_dtor()`` call. If it has a higher refcount the zval will stay alive with a NULL value.

There are two further macros for copying zvals, namely ``COPY_PZVAL_TO_ZVAL()`` and ``REPLACE_ZVAL_VALUE()``. Both are
used rather rarely and will not be discussed here.

Separating zvals
----------------

The macros described above are mainly used when you want to copy a zval to another storage location. A typical example
is copying a value into the ``return_value`` zval. There is a second second set of macros for "zval separation", which
are used in the context of copy-on-write. Their functionality is best understood by looking at the source code::

    #define SEPARATE_ZVAL(ppzv)                     \
        do {                                        \
            if (Z_REFCOUNT_PP((ppzv)) > 1) {        \
                zval *new_zv;                       \
                Z_DELREF_PP(ppzv);                  \
                ALLOC_ZVAL(new_zv);                 \
                INIT_PZVAL_COPY(new_zv, *(ppzv));   \
                *(ppzv) = new_zv;                   \
                zval_copy_ctor(new_zv);             \
            }                                       \
        } while (0)

If the refcount is one ``SEPARATE_ZVAL()`` won't do anything. If the refcount is larger it will remove one ref from the
old zval, copy it to a new zval and assign that new zval to ``*ppzv``. Note that the macro accepts a ``zval**`` and
will modify the ``zval*`` it points to.

How is this used practically? Imagine you want to modify an array offset like ``$array[42]``. To do so you first fetch
the ``zval**`` pointer to the stored ``zval*`` value. Due to the reference-counting you can't directly modify it (as
it could be shared with other places), so have to separate it first. The separation will either leave the old zval if
the refcount is one or it will perform a copy. In the latter case the new zval is assigned to ``*ppzv``, which in this
case is the storage location in the array.

Doing a simple copy with ``MAKE_COPY_ZVAL()`` wouldn't be sufficient here because the copied zval would not actually be
the zval stored in the array.

Directly using ``SEPARATE_ZVAL()`` before performing a zval modification doesn't yet account for the case where the zval
has is_ref=1, in which case the separation should not occur. To handle this case lets first look at the macros PHP
provides to handle the is_ref flag::

    Z_ISREF_P(zv_ptr)           /* Get if zval is reference */

    Z_SET_ISREF_P(zv_ptr)       /* Set is_ref=1 */
    Z_UNSET_ISREF_P(zv_ptr)     /* Set is_ref=0 */

    Z_SET_ISREF_TO_P(zv_ptr, 1) /* Same as Z_SET_ISREF_P(zv_ptr) */
    Z_SET_ISREF_TO_P(zv_ptr, 0) /* Same as Z_UNSET_ISREF_P(zv_ptr) */

Once again the macros are available in variants without suffix, ``_P`` suffix and ``_PP`` suffix, accepting a ``zval``,
``zval*`` or ``zval**`` respectively. Furthermore there is an older ``PZVAL_IS_REF()`` macro which is synonymous with
``Z_ISREF_P()``.

Using these PHP provides two more variants of ``SEPARATE_ZVAL()``::

    #define SEPARATE_ZVAL_IF_NOT_REF(ppzv)      \
        if (!PZVAL_IS_REF(*ppzv)) {             \
            SEPARATE_ZVAL(ppzv);                \
        }

    #define SEPARATE_ZVAL_TO_MAKE_IS_REF(ppzv)  \
        if (!PZVAL_IS_REF(*ppzv)) {             \
            SEPARATE_ZVAL(ppzv);                \
            Z_SET_ISREF_PP((ppzv));             \
        }

``SEPARATE_ZVAL_IF_NOT_REF()`` is the macro you'd usually use when modifying a zval according to copy-on-write.
``SEPARATE_ZVAL_TO_MAKE_IS_REF()`` is used when you want to turn a zval into a reference (e.g. for a by-reference
assignment or by-reference argument pass.) The latter is mainly used by the engine and only rarely in extension code.

There is another macro in the ``SEPARATE`` family, which works a bit differently from the other ones::

    #define SEPARATE_ARG_IF_REF(varptr) \
        if (PZVAL_IS_REF(varptr)) { \
            zval *original_var = varptr; \
            ALLOC_ZVAL(varptr); \
            INIT_PZVAL_COPY(varptr, original_var); \
            zval_copy_ctor(varptr); \
        } else { \
            Z_ADDREF_P(varptr); \
        }

The first difference is that this macro takes a ``zval*`` rather than a ``zval**``. As such it will not be able to
modify the ``zval*`` it separates. Furthermore this macro already increments the refcount for you, whereas the
``SEPARATE_ZVAL`` macros do not.

Apart from this it basically complements ``SEPARATE_ZVAL_IF_NO_REF()``: This time the separation happens when the
zval **is** a reference. It's mainly used to make sure that an argument passed to a function is a value, not a
reference.