Object handlers
===============

Nearly all operations on objects in PHP go through object handlers and every magic method or magic interface is
implemented with an object or class handler internally. Furthermore there are quite a few handlers which are not exposed
to userland PHP. For example internal classes can have custom comparison and cast behavior.

As the number of different object handlers is rather large we can only discuss examples (using the typed array
implementation from the last section) for a few of them. For all the others only a short description is provided.

An Overview
-----------

Here are all the object handlers with their signature and a small description.

.. c:member::
    zval *read_property(zend_object *object, zend_string *member, int type, void **cache_slot, zval *rv)
    zval *write_property(zend_object *object, zend_string *member, zval *value, void **cache_slot)
    int has_property(zend_object *zobj, zend_string *name, int has_set_exists, void **cache_slot)
    void unset_property(zend_object *zobj, zend_string *name, void **cache_slot)
    zval *get_property_ptr_ptr(zend_object *zobj, zend_string *name, int type, void **cache_slot)

    These handlers correspond to the ``__get``, ``__set``, ``__isset`` and ``__unset`` methods. ``get_property_ptr_ptr``
    is the internal equivalent of ``__get`` returning by reference. ``cache_slot`` is used to store the property
    offset and ``zend_property_info``. ``zval *rv`` in ``read_property`` provides a place for temporary zvals that
    are not stored in the object itself, like results of calls to ``__get``.

.. c:member::
    zval *read_dimension(zend_object *object, zval *offset, int type, zval *rv)
    void write_dimension(zend_object *object, zval *offset, zval *value)
    int has_dimension(zend_object *object, zval *offset, int check_empty)
    void unset_dimension(zend_object *object, zval *offset)

    This set of handlers is the internal representation of the ``ArrayAccess`` interface. ``zval *rv`` in
    ``read_dimension`` is used for temporary values returned from ``offsetGet`` and ``offsetExists``.

.. c:member::
    HashTable *get_properties(zend_object *zobj)
    HashTable *get_debug_info(zend_object *object, int *is_temp)

    Used to get the object properties as a hashtable. The former is more general purpose, for example it is also used
    for the ``get_object_vars`` function. The latter on the other hand is used exclusively to display properties in
    debugging functions like ``var_dump``. So even if your object does not provide any formal properties you can still
    have a meaningful debug output.

.. c:member::
    zend_function *get_method(zend_object **obj_ptr, zend_string *method_name, const zval *key)

    The ``get_method`` handler fetches the ``zend_function`` used to call a certain method. Either the ``method_name``
    or ``key`` must be passed. ``key`` is assumed to be lower case.

.. c:member::
    zend_function *get_constructor(zend_object *zobj)

    Like ``get_method``, but getting the constructor function. The most common reason to override this handler is to
    disallow manual construction by throwing an error in the handler.

.. c:member::
    int count_elements(zend_object *object, zend_long *count)

    This is just the internal way of implementing the ``Countable::count`` method. The function returns a
    ``zend_result`` and assigns the value to the ``zend_long *count`` pointer.

.. FIXME: Change return type of count_elements to zend_result to make it more obvious the count is not returned?

.. c:member::
    int compare(zval *o1, zval *o2)
    int cast_object(zend_object *readobj, zval *writeobj, int type)

    Internal classes have the ability to implement a custom compare behavior and override casting behavior for all
    types. Userland classes on the other hand only have the ability to override object to string casting through
    ``__toString``.

.. c:member::
    int get_closure(zend_object *obj, zend_class_entry **ce_ptr, zend_function **fptr_ptr, zend_object **obj_ptr, bool check_only)

    This handler is invoked when the object is used as a function, i.e. it is the internal version of ``__invoke``.
    The name derives from the fact that its main use is for the implementation of closures (the ``Closure`` class).

.. c:member::
    zend_string *get_class_name(const zend_object *zobj)

    This handler is used to get the class name from an object. There should be little reason to overwrite it. The only
    occasion that I can think of where this would be necessary is if you choose to create a custom object structure that
    does *not* contain the standard ``zend_object`` as a substructure. (This is entirely possible, but not usually done.)

.. c:member::
    zend_object *clone_obj(zend_object *old_object)
    HashTable *get_gc(zend_object *zobj, zval **table, int *n)

    The ``clone_obj`` handler is called when executing ``clone $old_object``. By default PHP performs a shallow clone
    on objects, which means properties containing objects are not be cloned but both the old and new object will point
    to the same object. The ``clone_obj`` allows for this behavior to be customized. It's also used to inhibit ``clone``
    altogether.

    The ``get_gc`` handler should return all variables that are held by the object, so cyclic dependencies can be
    properly collected. If the object doesn't maintain a property hashmap (because it doesn't store any dynamic
    properties) it can use ``table`` to store a pointer directly into the list of zvals, along with a count of
    properties.

.. c:member::
    void dtor_obj(zend_object *object)
    void free_obj(zend_object *object)

    ``dtor_obj`` is called before ``free_obj``. The object must remain in a valid state after dtor_obj finishes running.
    Unlike ``free_obj``, it is run prior to deactivation of the executor during shutdown, which allows user code to run.
    This handler is not guaranteed to be called (e.g. on fatal error), and as such should not be used to release
    resources or deallocate memory. Furthermore, releasing resources in this handler can break detection of memory
    leaks, as cycles may be broken early. ``dtor_obj`` should be used only to call user destruction hooks, such as
    ``__destruct``.

    ``free_obj`` should release any resources the object holds, without freeing the object structure itself. The object
    does not need to be in a valid state after ``free_obj`` finishes running. ``free_obj`` will always be invoked, even
    if the object leaks or a fatal error occurs. However, during shutdown it may be called once the executor is no
    longer active, in which case execution of user code may be skipped.

.. c:member::
    int do_operation(zend_uchar opcode, zval *result, zval *op1, zval *op2)

    ``do_operation`` is an optional handler that will be invoked for various arithmetic and binary operations on
    instances of the given class. This allows for operator overloading semantics to be implemented for custom classes.
    Examples for overloadable operators are ``+``, ``-``, ``*``, ``/``, ``++``, ``--``, ``!``.

.. c:member::
    int compare(zval *object1, zval *object2)

    The ``compare`` handler is a required handler that computes equality of the given object and another value. Note
    that the other value isn't necessarily an object of the same class, or even an object at all. The handler should
    return negative numbers if the lhs is smaller, 0 if they are equal, or a positive number is the lhs is larger. If
    the values are uncomparable ``ZEND_UNCOMPARABLE`` should be returned.

.. c:member::
    zend_array *get_properties_for(zend_object *object, zend_prop_purpose purpose)

    The ``get_properties_for`` can be used to customize the list of object properties returned for various purposes.
    The purposes are defined in ``zend_prop_purpose``, which currently entails ``print_r``, ``var_dump``, the
    ``(array)`` cast, ``serialize``, ``var_export`` and ``json_encode``.
