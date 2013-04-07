Object handlers: Part 1
=======================

In the previous sections you already had some contact with object handlers. In particular you should know how to create
the structure used to specify the handlers and how to implement cloning behavior using ``clone_obj``. But this is just
the beginning: Nearly all operations on objects in PHP go through object handlers and every magic method or magic
interface is implemented with an object or class handler internally. Furthermore there are quite a few handlers which
are not exposed to userland PHP. For example internal classes can have custom comparison and cast behavior.

As the number of different object handlers is rather large this section only covers a small part of them, leaving the
rest for later sections. The usage is illustrated on the typed array implementation from the previous section.

An Overview
-----------

Before getting into the details of individual handlers I'd first like to give a short overview over all the handlers
that are available as of this writing (26 in total). I'll list the name of the handler, its signature, as well as a
small description of its use.

.. c:member::
    zval *read_property(zval *object, zval *member, int type, const struct _zend_literal *key TSRMLS_DC)
    void write_property(zval *object, zval *member, zval *value, const struct _zend_literal *key TSRMLS_DC)
    int has_property(zval *object, zval *member, int has_set_exists, const struct _zend_literal *key TSRMLS_DC)
    void unset_property(zval *object, zval *member, const struct _zend_literal *key TSRMLS_DC)
    zval **get_property_ptr_ptr(zval *object, zval *member, const struct _zend_literal *key TSRMLS_DC)

    These handlers correspond to the ``__get``, ``__set``, ``__isset`` and ``__unset`` methods. ``get_property_ptr_ptr``
    is the internal equivalent of ``__get`` returning by reference. The ``zend_literal *key`` passed to these functions
    exists as an optimization, for example it contains a precomputed hash of of the property name.

.. c:member::
    zval *read_dimension(zval *object, zval *offset, int type TSRMLS_DC)
    void write_dimension(zval *object, zval *offset, zval *value TSRMLS_DC)
    int has_dimension(zval *object, zval *member, int check_empty TSRMLS_DC)
    void unset_dimension(zval *object, zval *offset TSRMLS_DC)

    This set of handlers is the internal representation of the ``ArrayAccess`` interface.

.. c:member::
    void set(zval **object, zval *value TSRMLS_DC)
    zval *get(zval *object TSRMLS_DC)

    These handlers get/set the "object value". They can be used to override compound assignment operators (like ``+=``
    or ``++``) and exist mainly for the purpose of proxy objects. In practice they are rarely used.

.. c:member::
    HashTable *get_properties(zval *object TSRMLS_DC)
    HashTable *get_debug_info(zval *object, int *is_temp TSRMLS_DC)

    Used to get the object properties as a hashtable. The former is more general purpose, for example it is also used
    for the ``get_object_vars`` function. The latter on the other hand is used exclusively to display properties in
    debugging functions like ``var_dump``. So even if your object does not provide any formal properties you can still
    have a meaningful debug output.

.. c:member::
    union _zend_function *get_method(zval **object_ptr, char *method, int method_len, const struct _zend_literal *key TSRMLS_DC)
    int call_method(const char *method, INTERNAL_FUNCTION_PARAMETERS)

    The ``get_method`` handler fetches the ``zend_function`` used to call a certain method. If there is no particular
    ``zend_function`` that you want to invoke, but you rather want a ``__call``-like catch-all behavior, then
    ``get_method`` can signal that it is a ``ZEND_OVERLOADED_FUNCTION`` in which case the ``call_method`` handler will
    be used instead.

.. c:member:: union _zend_function *get_constructor(zval *object TSRMLS_DC)

    Like ``get_method``, but getting the constructor function. The most common reason to override this handler is to
    disallow manual construction by throwing an error in the handler.

.. c:member:: int count_elements(zval *object, long *count TSRMLS_DC)

    This is just the internal way of implementing the ``Countable::count`` method.

.. c:member::
    int compare_objects(zval *object1, zval *object2 TSRMLS_DC)
    int cast_object(zval *readobj, zval *retval, int type TSRMLS_DC)

    Internal classes have the ability to implement a custom compare behavior and override casting behavior for all
    types. Userland classes on the other hand only have the ability to override object to string casting through
    ``__toString``.

.. c:member:: int get_closure(zval *obj, zend_class_entry **ce_ptr, union _zend_function **fptr_ptr, zval **zobj_ptr TSRMLS_DC)

    This handler is invoked when the the object is used as a function, i.e. it is the internal version of ``__invoke``.
    The name derives from the fact that its main use is for the implementation of closures (the ``Closure`` class).

.. c:member::
    zend_class_entry *get_class_entry(const zval *object TSRMLS_DC)
    int get_class_name(const zval *object, const char **class_name, zend_uint *class_name_len, int parent TSRMLS_DC)

    These two handlers are used to get the class entry and class name from an object. There should be little reason to
    overwrite them. The only occasion that I can think of where this would be necessary is if you choose to create a
    custom object structure that does *not* contain the standard ``zend_object`` as a substructure. (This is entirely
    possible, but not usually done.)

.. c:member::
    void add_ref(zval *object TSRMLS_DC)
    void del_ref(zval *object TSRMLS_DC)
    zend_object_value clone_obj(zval *object TSRMLS_DC)
    HashTable *get_gc(zval *object, zval ***table, int *n TSRMLS_DC)

    This set of handlers is used for various object maintenance tasks. ``add_ref`` is called when a new zval starts
    referencing the object, ``del_ref`` is called when a reference is removed. By default these handlers will change
    the refcount in the object store. Once again there should be virtually no reason to overwrite them. The only
    application I can think of is when you choose *not* to use the Zend object store, but rather use some custom
    storage facility.

    You already know the ``clone_obj`` handler, so I'll jump right to ``get_gc``: This handler should return all
    variables that are held by the object, so cyclic dependencies can be properly collected.

Implementing array access using object handlers
-----------------------------------------------

In the previous section the ``ArrayAccess`` interface was used to provide array-like behavior for the buffer views. Now
we want to improve the implementation by using the respective ``*_dimension`` object handlers. These same handlers are
also used to implement ``ArrayAccess``, but providing a custom implementation will be faster as the overhead of calling
methods is avoided.

The object handlers for dimensions are ``read_dimension``, ``write_dimension``, ``has_dimension`` and
``unset_dimension``. They all take the object zval as first argument and the offset zval as second. For our purposes
the offset has to be an integer, so let's first introduce a helper function for getting the long value from a zval (in
order to avoid all the repeating cast code)::

    static long get_long_from_zval(zval *zv)
    {
        if (Z_TYPE_P(zv)) {
            return Z_LVAL_P(zv);
        } else {
            long lval;
            Z_ADDREF_P(zv);
            convert_to_long_ex(&zv);
            lval = Z_LVAL_P(zv);
            zval_ptr_dtor(&zv);
            return lval;
        }
    }

Now writing the respective handlers is rather straightforward. For example, this is how the ``read_dimension`` handler
looks like::

    static zval *array_buffer_view_read_dimension(zval *object, zval *zv_offset, int type TSRMLS_DC)
    {
        buffer_view_object *intern = zend_object_store_get_object(object TSRMLS_CC);
        zval *retval;
        long offset;

        if (!zv_offset) {
            zend_throw_exception(NULL, "Cannot append to a typed array", 0 TSRMLS_CC);
            return NULL;
        }

        offset = get_long_from_zval(zv_offset);
        if (offset < 0 || offset >= intern->length) {
            zend_throw_exception(NULL, "Offset is outside the buffer range", 0 TSRMLS_CC);
            return NULL;
        }

        retval = buffer_view_offset_get(intern, offset);
        Z_DELREF_P(retval); /* Refcount should be 0 if not referenced from ext / engine */
        return retval;
    }

Something that is slightly odd about this handler is the ``Z_DELREF_P(retval)`` at the end: ``read_dimension`` is
expected to return a zval with refcount 0 if the returned zval isn't used anywhere else (as it is the case for us). The
engine will increment the refcount itself. The refcount 0 also tells the engine that reference operations on the return
value don't make sense (as nothing would be actually modified).

Another thing that might seem strange is that we have to check for array appends (which are signaled by
``zv_offset = NULL``) in a *read* handler. This is related to ``type`` parameter that was left unused in the above
code. This parameter specifies the context in which the read occurred. For "normal" ``$foo[0]`` style reads the ``type``
will be ``BP_VAR_R``, but it can also be one of ``BP_VAR_W``, ``BP_VAR_RW``, ``BP_VAR_IS`` or ``BP_VAR_UNSET``. To
understand when "non-read" types like this can happen consider the following examples:

.. code-block:: php

    <?php

    $foo[0][1];        // [0] is a read_dimension(..., BP_VAR_R),     [1] is a read_dimension(..., BP_VAR_R)
    $foo[0][1] = $bar; // [0] is a read_dimension(..., BP_VAR_W),     [1] is a write_dimension
    $foo[][1] = $bar;  // []  is a read_dimension(..., BP_VAR_W),     [1] is a write_dimension
    isset($foo[0][1]); // [0] is a read_dimension(..., BP_VAR_IS),    [1] is a has_dimension
    unset($foo[0][1]); // [0] is a read_dimension(..., BP_VAR_UNSET), [1] is a unset_dimension

As you can see the other ``BP_VAR`` types occur with nested dimension access. In this case only the outermost access
calls the actual handler for the operation, the inner dimension accesses go through the read handler with the respective
type. So if the ``[]`` append operator is used in a nested was the ``read_dimension`` handler can be called with the
offset being ``NULL``.

The ``type`` parameter can be used to change the behavior depending on the context. For example ``isset`` is usually
expected not to throw any warnings, errors or exceptions. We could honor this by explicitly checking for the
``BP_VAR_IS`` type::

    if (type == BP_VAR_IS)
        return &EG(uninitialized_zval_ptr);
    }

But as in our particular case nested dimension access doesn't really make sense we don't need to worry much about any
such behaviors.

The remaining handlers are similar to ``read_dimension`` (but less tricky)::

    static void array_buffer_view_write_dimension(zval *object, zval *zv_offset, zval *value TSRMLS_DC)
    {
        buffer_view_object *intern = zend_object_store_get_object(object TSRMLS_CC);
        long offset;

        if (!zv_offset) {
            zend_throw_exception(NULL, "Cannot append to a typed array", 0 TSRMLS_CC);
            return;
        }

        offset = get_long_from_zval(zv_offset);
        if (offset < 0 || offset >= intern->length) {
            zend_throw_exception(NULL, "Offset is outside the buffer range", 0 TSRMLS_CC);
            return;
        }

        buffer_view_offset_set(intern, offset, value);
    }

    static int array_buffer_view_has_dimension(zval *object, zval *zv_offset, int check_empty TSRMLS_DC)
    {
        buffer_view_object *intern = zend_object_store_get_object(object TSRMLS_CC);
        long offset = get_long_from_zval(zv_offset);

        if (offset < 0 || offset >= intern->length) {
            return 0;
        }

        if (check_empty) {
            int retval;
            zval *value = buffer_view_offset_get(intern, offset);
            retval = zend_is_true(value);
            zval_ptr_dtor(&value);
            return retval;
        }

        return 1;
    }

    static void array_buffer_view_unset_dimension(zval *object, zval *zv_offset TSRMLS_DC)
    {
        zend_throw_exception(NULL, "Cannot unset offsets in a typed array", 0 TSRMLS_CC);
    }

There is little to say about these handlers. The only thing worth noting is the ``check_empty`` parameter of the
``has_dimension`` handler. If this parameter is ``0`` then it's an ``isset`` call, if it is ``1`` then it's an ``empty``
call. For ``isset`` the mere existence is checked, for ``empty`` the truthyness.

Lastly the new handlers need to be assigned in ``MINIT``::

    memcpy(&array_buffer_view_handlers, zend_get_std_object_handlers(), sizeof(zend_object_handlers));
    array_buffer_view_handlers.clone_obj       = array_buffer_view_clone; /* from previous section already */
    array_buffer_view_handlers.read_dimension  = array_buffer_view_read_dimension;
    array_buffer_view_handlers.write_dimension = array_buffer_view_write_dimension;
    array_buffer_view_handlers.has_dimension   = array_buffer_view_has_dimension;
    array_buffer_view_handlers.unset_dimension = array_buffer_view_unset_dimension;

And now all array operations should work just as previously, only faster (for me using the handlers directly was about
four times faster than ``ArrayAccess``).

Honoring inheritance
--------------------

One key issue that has to be considered whenever you implement object handlers is that they apply all the way down the
inheritance chain. If the user extends one of the view classes it will still use the same handlers. So if the dimension
access handlers are overridden the user will no longer be able to use ``ArrayAccess`` in an inheriting class.

A very simple way to solve this issue is to check whether the class was extended in the dimension handlers and fall back
to the standard handlers in this case::

    if (intern->std.ce->parent) {
        return zend_get_std_object_handlers()->read_dimension(object, zv_offset, type TSRMLS_CC);
    }

Comparison of view objects
--------------------------

Right now view objects will always be considered equal if they are of the same type (and have no properties). That's
not really what we want. Instead we should implement our own comparison behavior: Two buffer views should be considered
equal if they use the same buffer, with the same offset, same length and same type. Furthermore their class entry should
match (so inheriting classes aren't considered equal). Additionally the properties should be equal, or to simplify our
implementation just shouldn't exist. In other words: Two buffer views are equal if their internal objects are the same
byte for byte. We can easily check this with ``memcmp``::

    static int array_buffer_view_compare_objects(zval *obj1, zval *obj2 TSRMLS_DC)
    {
        buffer_view_object *intern1 = zend_object_store_get_object(obj1 TSRMLS_CC);
        buffer_view_object *intern2 = zend_object_store_get_object(obj2 TSRMLS_CC);

        if (memcmp(intern1, intern2, sizeof(buffer_view_object)) == 0) {
            return 0; /* equal */
        } else {
            return 1; /* not orderable */
        }
    }

As you can see the ``compare_objects`` handler takes two objects and returns how those two objects relate. The return
value is one of -1 (smaller), 0 (equal) and 1 (greater).

In our case the smaller/greater relationship doesn't really make sense, so we want ``$view1 < $view2`` and
``$view1 > $view2`` to always be false. This can be done by returning 1 from the handler if the objects are not equal.
You might wonder why this works, after all 1 means "greater" so one could expect ``$view1 > $view2`` to return true.
The reason why this trick works is that PHP automatically translates ``$a > $b`` to ``$b < $a`` (and ``$a >= $b`` to
``$b <= $a``). Thus always the "less than" relationship is used and as we're returning 1 (regardless of order) any
comparison will be false.

A similar comparison handler can be written for the ``ArrayBuffer`` class too.

Debug information
-----------------

If you dumped a buffer view object with ``var_dump`` or ``print_r`` right now, you wouldn't get any useful information:

.. code-block:: none

    object(Int8Array)#2 (0) {
    }

It would be much more helpful if instead the contents of the array were printed. Such a behavior can be easily
implemented using the ``get_debug_info`` handler::

    static HashTable *array_buffer_view_get_debug_info(zval *obj, int *is_temp TSRMLS_DC)
    {
        buffer_view_object *intern = zend_object_store_get_object(obj TSRMLS_CC);
        HashTable *props = Z_OBJPROP_P(obj);
        HashTable *ht;
        int i;

        ALLOC_HASHTABLE(ht);
        ZEND_INIT_SYMTABLE_EX(ht, intern->length + zend_hash_num_elements(props), 0);
        zend_hash_copy(ht, props, (copy_ctor_func_t) zval_add_ref, NULL, sizeof(zval *));

        *is_temp = 1;

        for (i = 0; i < intern->length; ++i) {
            zval *value = buffer_view_offset_get(intern, i);
            zend_hash_index_update(ht, i, (void *) &value, sizeof(zval *), NULL);
        }

        return ht;
    }

The handler creates a hashtable using ``ZEND_INIT_SYMTABLE_EX`` to provide a size-hint, copies the properties (in case
the user added custom properties) and then loops through the view and inserts all its elements into the hash.

Into the additional ``is_temp`` parameter the value ``1`` is written, signifying that we are using a temporary
hashtable that has to be freed later. Alternatively we could write ``0`` into the pointer, in which case we would have
to store the hashtable somewhere else and manually free it (you'll find that many objects have some kind of
``debug_info`` field in their internal structure that is used for this purpose.)

A small example of the kind of output this produces:

.. code-block:: php

    <?php
    $buffer = new ArrayBuffer(4);

    $view = new Int8Array($buffer);
    $view->foo = 'bar';
    $view[0] = 10; $view[1] = 20; $view[2] = -10; $view[3] = -20;

    var_dump($view);

    // outputs

    object(Int8Array)#2 (5) {
      ["foo"]=>
      string(3) "bar"
      [0]=>
      int(10)
      [1]=>
      int(20)
      [2]=>
      int(-10)
      [3]=>
      int(-20)
    }

One more handler that could be implemented for typed arrays is ``count_elements``, i.e. the internal equivalent of
``Countable::count()``. There is nothing special about that handler though, so I'm leaving this as an exercise for the
reader (just don't forget the inheritance check!)

This concludes our first dabbling with object handlers. In the next section we'll add support for iteration over typed
arrays.