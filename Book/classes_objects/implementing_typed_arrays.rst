Implementing typed arrays
=========================

The previous two sections have been talking about the class system rather abstractly. In this section on the other hand
I'd like to guide you through the implementation of a "real" class: A typed array. I use this as an example for two
reasons: Firstly, typed arrays are something where it really makes sense to implement them internally. They are rather
hard to implement in userland PHP and an internal implementation can use both less memory and be a lot faster. Secondly,
typed arrays are good to show off some of PHP's object and class handlers. For example they need offset access, element
counting, iteration, serialization and debug information.

Array buffers and views
-----------------------

What we'll implement in this section is a reduced version of JavaScript's ArrayBuffer system. An ``ArrayBuffer`` is just
a chunk of memory with a fixed size. The ``ArrayBuffer`` by itself cannot be read or written to, it is just an object
representing the memory.

In order to read from or write to the buffer you have to create a view on it. E.g. to interpret the buffer as an array
of signed 32-bit integers you create a ``Int32Array`` view. To view it as an array of unsigned 8-bit numbers instead you
can use a ``UInt8Array``. It is possible to have several views on the same data, so data can be interpreted both as an
int32 and a uint8.

A small usage example:

.. code-block:: php

    <?php

    // allocate a buffer containing 256 bytes
    $buffer = new ArrayBuffer(256);

    // create an int32 view on the buffer with 256 / 8 = 32 elements
    $int32 = new Int32Array($buffer);

    // create a uint8 view on the same buffer with 256 / 1 = 256 elements
    $uint8 = new UInt8Array($buffer);

    // fill the uint8 view with values from 0 to 255
    for ($i = 0; $i < 256; ++$i) {
        $uint8[$i] = $i;
    }

    // now read the filled buffer interpreting it as signed 32-bit integers
    for ($i = 0; $i < 32; ++$i) {
        echo $int32[$i], "\n";
    }

This kind of buffer + view system is handy for many purposes, so it'll be the system that will be implemented here. To
not make this overly long we won't implement the whole JS API, only the most important parts of it. Furthermore I won't
spend much time considering details of the implementations like overflow behavior and endianness. Those are very
important considerations for a "real" implementation, but for our purposes it's not really relevant, so I'll just stick
with the behaviors that you get "by default" (i.e. with least code).

The ``ArrayBuffer``
-------------------

The ``ArrayBuffer`` is a very simple object, that only needs to allocate and store a buffer and its length. Thus the
internal structure could look like this:

.. code-block:: c

    typedef struct _buffer_object {
        zend_object std;

        void *buffer;
        size_t length;
    } buffer_object;

    /* Use the chance to declare CE and handlers too */
    zend_class_entry *array_buffer_ce;
    zend_object_handlers array_buffer_handlers;

The create and free handlers are similarly simple and look nearly the same as the ones in the previous section:

.. code-block:: c

    static void array_buffer_free_object_storage(buffer_object *intern TSRMLS_DC)
    {
        zend_object_std_dtor(&intern->std TSRMLS_CC);

        if (intern->buffer) {
            efree(intern->buffer);
        }

        efree(intern);
    }

    zend_object_value array_buffer_create_object(zend_class_entry *class_type TSRMLS_DC)
    {
        zend_object_value retval;

        buffer_object *intern = emalloc(sizeof(buffer_object));
        memset(intern, 0, sizeof(buffer_object));

        zend_object_std_init(&intern->std, class_type TSRMLS_CC);
        object_properties_init(&intern->std, class_type);

        retval.handle = zend_objects_store_put(intern,
            (zend_objects_store_dtor_t) zend_objects_destroy_object,
            (zend_objects_free_object_storage_t) array_buffer_free_object_storage,
            NULL TSRMLS_CC
        );
        retval.handlers = &array_buffer_handlers;

        return retval;
    }

The ``create_object`` handler does not yet allocate the buffer, this is done in the constructor (because it depends on
the buffer length, which is a ctor parameter):

.. code-block:: c

    PHP_METHOD(ArrayBuffer, __construct)
    {
        buffer_object *intern;
        long length;
        zend_error_handling error_handling;

        zend_replace_error_handling(EH_THROW, NULL, &error_handling TSRMLS_CC);
        if (zend_parse_parameters(ZEND_NUM_ARGS() TSRMLS_CC, "l", &length) == FAILURE) {
            zend_restore_error_handling(&error_handling TSRMLS_CC);
            return;
        }

        if (length <= 0) {
            zend_throw_exception(NULL, "Buffer length must be positive", 0 TSRMLS_CC);
            return;
        }

        intern = zend_object_store_get_object(getThis() TSRMLS_CC);

        intern->buffer = emalloc(length);
        intern->length = length;

        memset(intern->buffer, 0, length);
    }

As we are now writing object-oriented code we no longer throw errors, but rather exceptions. This is done using
``zend_throw_exception``, which takes the exception class entry, the exception message and the error code. If you pass
``NULL`` as the exception CE then you'll get a default exception, i.e. ``Exception``.

Especially for the ``__construct`` method is it important that you throw an exception in case of an error to avoid
ending up with a partially constructed object. That's also the reason why the above code replaces the error handling
mode during parameter parsing. Normally ``zend_parse_parameters`` would only throw a warning on invalid parameters,
which wouldn't be enough in this case. By setting the error mode to ``EH_THROW`` the warning is automatically converted
into an exception.

The error handling mode can be changed using ``zend_replace_error_handling``. It takes one of ``EH_NORMAL`` (default
error reporting), ``EH_SUPPRESS`` (silence all errors) or ``EH_THROW`` (throw errors as exceptions) as the first
argument. The second argument can be used to specify the exception CE for the ``EH_THROW`` mode. If ``NULL`` is passed
the default ``Exception`` class is used. As the last parameter a pointer to a ``zend_error_handling`` structure is
passed, into which the previous error mode is backed up. This structure is later passed to
``zend_restore_error_handling`` to get the old mode back.

Apart from the create handler you also have to handle cloning. For the ``ArrayBuffer`` this is as simple as just
copying the allocated buffer:

.. code-block:: c

    static zend_object_value array_buffer_clone(zval *object TSRMLS_DC)
    {
        buffer_object *old_object = zend_object_store_get_object(object TSRMLS_CC);
        zend_object_value new_object_val = array_buffer_create_object(Z_OBJCE_P(object) TSRMLS_CC);
        buffer_object *new_object = zend_object_store_get_object_by_handle(
            new_object_val.handle TSRMLS_CC
        );

        zend_objects_clone_members(
            &new_object->std, new_object_val,
            &old_object->std, Z_OBJ_HANDLE_P(object) TSRMLS_CC
        );

        new_object->buffer = emalloc(old_object->length);
        new_object->length = old_object->length;

        memcpy(new_object->buffer, old_object->buffer, old_object->length);

        return new_object_val;
    }

And finally getting everything together in ``MINIT``:

.. code-block:: c

    ZEND_BEGIN_ARG_INFO_EX(arginfo_buffer_ctor, 0, 0, 1)
        ZEND_ARG_INFO(0, length)
    ZEND_END_ARG_INFO()

    const zend_function_entry array_buffer_functions[] = {
        PHP_ME(ArrayBuffer, __construct, arginfo_buffer_ctor, ZEND_ACC_PUBLIC|ZEND_ACC_CTOR)
        PHP_FE_END
    };

    MINIT_FUNCTION(buffer)
    {
        zend_class_entry tmp_ce;

        INIT_CLASS_ENTRY(tmp_ce, "ArrayBuffer", array_buffer_functions);
        array_buffer_ce = zend_register_internal_class(&tmp_ce TSRMLS_CC);
        array_buffer_ce->create_object = array_buffer_create_object;

        memcpy(&array_buffer_handlers, zend_get_std_object_handlers(), sizeof(zend_object_handlers));
        array_buffer_handlers.clone_obj = array_buffer_clone;

        return SUCCESS;
    }

The buffer views
----------------

The buffer views will be a good bit more work. We'll implement 8 different view classes which all share one
implementation, namely ``Int8Array``, ``UInt8Array``, ``Int16Array``, ``UInt16Array``, ``Int32Array``, ``UInt32Array``,
``FloatArray`` and ``DoubleArray``. The class registration code looks as follows:

.. code-block:: c

    zend_class_entry *int8_array_ce;
    zend_class_entry *uint8_array_ce;
    zend_class_entry *int16_array_ce;
    zend_class_entry *uint16_array_ce;
    zend_class_entry *int32_array_ce;
    zend_class_entry *uint32_array_ce;
    zend_class_entry *float_array_ce;
    zend_class_entry *double_array_ce;

    zend_object_handlers array_buffer_view_handlers;

    /* ... There will be a lot more code coming in between ... */

    PHP_MINIT_FUNCTION(buffer)
    {
        zend_class_entry tmp_ce;

        /* ... ArrayBuffer stuff here ... */

    #define DEFINE_ARRAY_BUFFER_VIEW_CLASS(class_name, type)                      \
        INIT_CLASS_ENTRY(tmp_ce, #class_name, array_buffer_view_functions);       \
        type##_array_ce = zend_register_internal_class(&tmp_ce TSRMLS_CC);        \
        type##_array_ce->create_object = array_buffer_view_create_object;         \
        zend_class_implements(type##_array_ce TSRMLS_CC, 1, zend_ce_arrayaccess);

        DEFINE_ARRAY_BUFFER_VIEW_CLASS(Int8Array,   int8);
        DEFINE_ARRAY_BUFFER_VIEW_CLASS(UInt8Array,  uint8);
        DEFINE_ARRAY_BUFFER_VIEW_CLASS(Int16Array,  int16);
        DEFINE_ARRAY_BUFFER_VIEW_CLASS(Uint16Array, uint16);
        DEFINE_ARRAY_BUFFER_VIEW_CLASS(Int32Array,  int32);
        DEFINE_ARRAY_BUFFER_VIEW_CLASS(UInt32Array, uint32);
        DEFINE_ARRAY_BUFFER_VIEW_CLASS(FloatArray,  float);
        DEFINE_ARRAY_BUFFER_VIEW_CLASS(DoubleArray, double);

    #undef DEFINE_ARRAY_BUFFER_VIEW_CLASS

        memcpy(&array_buffer_view_handlers, zend_get_std_object_handlers(), sizeof(zend_object_handlers));
        array_buffer_view_handlers.clone_obj = array_buffer_view_clone;

        return SUCCESS;
    }

To avoid typing out the same code again and a again a temporary macro is used. It initializes the class entry (always
with the same functions), registers the class, assigns the create handler (which is also the same for all classes) and
implements the ``ArrayAccess`` interface. The macro uses the magic ``#`` and ``##`` operators, which were introduced in
[Some Ref].

The ``array_buffer_view_functions`` are declared as follows:

.. code-block:: c

    ZEND_BEGIN_ARG_INFO_EX(arginfo_buffer_view_ctor, 0, 0, 1)
        ZEND_ARG_INFO(0, buffer)
    ZEND_END_ARG_INFO()

    ZEND_BEGIN_ARG_INFO_EX(arginfo_buffer_view_offset, 0, 0, 1)
        ZEND_ARG_INFO(0, offset)
    ZEND_END_ARG_INFO()

    ZEND_BEGIN_ARG_INFO_EX(arginfo_buffer_view_offset_set, 0, 0, 2)
        ZEND_ARG_INFO(0, offset)
        ZEND_ARG_INFO(0, value)
    ZEND_END_ARG_INFO()

    const zend_function_entry array_buffer_view_functions[] = {
        PHP_ME_MAPPING(__construct, array_buffer_view_ctor, arginfo_buffer_view_ctor, ZEND_ACC_PUBLIC|ZEND_ACC_CTOR)

        /* ArrayAccess */
        PHP_ME_MAPPING(offsetGet, array_buffer_view_offset_get, arginfo_buffer_view_offset, ZEND_ACC_PUBLIC)
        PHP_ME_MAPPING(offsetSet, array_buffer_view_offset_set, arginfo_buffer_view_offset_set, ZEND_ACC_PUBLIC)
        PHP_ME_MAPPING(offsetExists, array_buffer_view_offset_exists, arginfo_buffer_view_offset, ZEND_ACC_PUBLIC)
        PHP_ME_MAPPING(offsetUnset, array_buffer_view_offset_unset, arginfo_buffer_view_offset, ZEND_ACC_PUBLIC)

        PHP_FE_END
    };

The new thing here is that instead of ``PHP_ME`` the macro ``PHP_ME_MAPPING`` is used. The difference is that
``PHP_ME`` maps to a ``PHP_METHOD`` whereas ``PHP_ME_MAPPING`` maps to a ``PHP_FUNCTION``. An example:

.. code-block:: c

    PHP_ME(ArrayBufferView, offsetGet, arginfo_buffer_view_offset, ZEND_ACC_PUBLIC)
    // maps to
    PHP_METHOD(ArrayBufferView, offsetGet) { ... }

    PHP_ME_MAPPING(offsetGet, array_buffer_view_offset_get, arginfo_buffer_view_offset, ZEND_ACC_PUBLIC)
    // maps to
    PHP_FUNCTION(array_buffer_view_offset_get) { ... }

What you have to realize here is that ``PHP_FUNCTION`` and ``PHP_METHOD`` really have nothing to do with PHP functions
or methods, they are just macros that define a function with a certain name and a certain set of parameters. That's
why you can register a "function" as a method (and you can also define a method with one name, but register it with
a different). This is in particular useful when you want to support both an OO interface and a procedural API.

In this case I chose to use ``PHP_ME_MAPPING`` to signal that there is no real ``ArrayBufferView`` class, rather there
is a set of functions that is shared by several classes.

Getting back to the implementation one has to consider what the internal structure for buffer views needs to store:
Firstly it needs a way to discriminate the different view classes, i.e. some kind of type tag. Secondly it needs to
store the zval of the buffer it operates on. And thirdly there has to be a member that can be used to access the buffer
as different types.

Additional out implementation will store the offset and length of the view. Those are used to create views that don't
use the entire buffer. E.g. ``new Int32Array($buffer, 18, 24)`` should create a view that starts 18 bytes into the buffer
and contains a total of 24 elements.

This is how the resulting structure could look like:

.. code-block:: c

    typedef enum _buffer_view_type {
        buffer_view_int8,
        buffer_view_uint8,
        buffer_view_int16,
        buffer_view_uint16,
        buffer_view_int32,
        buffer_view_uint32,
        buffer_view_float,
        buffer_view_double
    } buffer_view_type;

    typedef struct _buffer_view_object {
        zend_object std;

        zval *buffer_zval;

        union {
            int8_t   *as_int8;
            uint8_t  *as_uint8;
            int16_t  *as_int16;
            uint16_t *as_uint16;
            int32_t  *as_int32;
            uint32_t *as_uint32;
            float    *as_float;
            double   *as_double;
        } buf;

        size_t offset;
        size_t length;

        buffer_view_type type;
    } buffer_view_object;

The exact-width integer types used above (``int8_t``, ...) are part of the ``stdint.h`` header. Sadly this header isn't
always available on Windows, so a replacement header (that PHP natively provides) has to be included in this case:

.. code-block:: c

    #if defined(PHP_WIN32)
    # include "win32/php_stdint.h"
    #elif defined(HAVE_STDINT_H)
    # include <stdint.h>
    #endif

The free and create handlers for the above data structure are rather straightforward again:

.. code-block:: c

    static void array_buffer_view_free_object_storage(buffer_view_object *intern TSRMLS_DC)
    {
        zend_object_std_dtor(&intern->std TSRMLS_CC);

        if (intern->buffer_zval) {
            zval_ptr_dtor(&intern->buffer_zval);
        }

        efree(intern);
    }

    zend_object_value array_buffer_view_create_object(zend_class_entry *class_type TSRMLS_DC)
    {
        zend_object_value retval;

        buffer_view_object *intern = emalloc(sizeof(buffer_view_object));
        memset(intern, 0, sizeof(buffer_view_object));

        zend_object_std_init(&intern->std, class_type TSRMLS_CC);
        object_properties_init(&intern->std, class_type);

        {
            zend_class_entry *base_class_type = class_type;

            while (base_class_type->parent) {
                base_class_type = base_class_type->parent;
            }

            if (base_class_type == int8_array_ce) {
                intern->type = buffer_view_int8;
            } else if (base_class_type == uint8_array_ce) {
                intern->type = buffer_view_uint8;
            } else if (base_class_type == int16_array_ce) {
                intern->type = buffer_view_uint16;
            } else if (base_class_type == int32_array_ce) {
                intern->type = buffer_view_int32;
            } else if (base_class_type == uint32_array_ce) {
                intern->type = buffer_view_uint32;
            } else if (base_class_type == float_array_ce) {
                intern->type = buffer_view_float;
            } else if (base_class_type == double_array_ce) {
                intern->type = buffer_view_double;
            } else {
                /* Should never happen */
                zend_error(E_ERROR, "Buffer view does not have a valid base class");
            }
        }

        retval.handle = zend_objects_store_put(intern,
            (zend_objects_store_dtor_t) zend_objects_destroy_object,
            (zend_objects_free_object_storage_t) array_buffer_view_free_object_storage,
            NULL TSRMLS_CC
        );
        retval.handlers = &array_buffer_view_handlers;

        return retval;
    }

The ``create_object`` handler contains some extra code to first find the base class of the instantiated class and then
figure out which buffer view type it corresponds to. It's necessary to go up the ``parent`` chain to make sure that
everything will work fine if one of the classes is extended. The creation handler doesn't do particularly much, the main
happens in the constructor:

.. code-block:: c

    PHP_FUNCTION(array_buffer_view_ctor)
    {
        zval *buffer_zval;
        long offset = 0, length = 0;
        buffer_view_object *view_intern;
        buffer_object *buffer_intern;
        zend_error_handling error_handling;

        zend_replace_error_handling(EH_THROW, NULL, &error_handling TSRMLS_CC);
        if (zend_parse_parameters(ZEND_NUM_ARGS() TSRMLS_CC, "O|ll", &buffer_zval, array_buffer_ce, &offset, &length) == FAILURE) {
            zend_restore_error_handling(&error_handling TSRMLS_CC);
            return;
        }

        view_intern = zend_object_store_get_object(getThis() TSRMLS_CC);
        buffer_intern = zend_object_store_get_object(buffer_zval TSRMLS_CC);

        view_intern->buffer_zval = buffer_zval;

        if (offset < 0) {
            zend_throw_exception(NULL, "Offset must be non-negative", 0 TSRMLS_CC);
            return;
        }
        if (offset >= buffer_intern->length) {
            zend_throw_exception(NULL, "Offset has to be smaller than the buffer length", 0 TSRMLS_CC);
            return;
        }

        view_intern->offset = offset;

        if (length < 0) {
            zend_throw_exception(NULL, "Length must be positive or zero", 0 TSRMLS_CC);
            return;
        }

        {
            size_t bytes_per_element = buffer_view_get_bytes_per_element(view_intern);
            size_t max_length = (buffer_intern->length - offset) / bytes_per_element;

            if (length == 0) {
                view_intern->length = max_length;
            } else if (length > max_length) {
                zend_throw_exception(NULL, "Length is larger than the buffer", 0 TSRMLS_CC);
                return;
            } else {
                view_intern->length = length;
            }
        }

        view_intern->buf.as_int8 = buffer_intern->buffer;
        view_intern->buf.as_int8 += offset;
    }

The code is mostly error checking, with a few assignments to the internal structure sprinkled in between. The code also
uses the helper function ``buffer_view_get_bytes_per_element`` which does exactly what it says:

.. code-block:: c

    size_t buffer_view_get_bytes_per_element(buffer_view_object *intern)
    {
        switch (intern->type)
        {
            case buffer_view_int8:
            case buffer_view_uint8:
                return 1;
            case buffer_view_int16:
            case buffer_view_uint16:
                return 2;
            case buffer_view_int32:
            case buffer_view_uint32:
            case buffer_view_float:
                return 4;
            case buffer_view_double:
                return 8;
            default:
                /* Should never happen */
                zend_error_noreturn(E_ERROR, "Invalid buffer view type");
        }
    }

The only missing piece from the construction logic is the clone handler, which doesn't do much more than copying the
internal members and adding a ref to the buffer zval:

.. code-block:: c

    static zend_object_value array_buffer_view_clone(zval *object TSRMLS_DC)
    {
        buffer_view_object *old_object = zend_object_store_get_object(object TSRMLS_CC);
        zend_object_value new_object_val = array_buffer_view_create_object(
            Z_OBJCE_P(object) TSRMLS_CC
        );
        buffer_view_object *new_object = zend_object_store_get_object_by_handle(
            new_object_val.handle TSRMLS_CC
        );

        zend_objects_clone_members(
            &new_object->std, new_object_val,
            &old_object->std, Z_OBJ_HANDLE_P(object) TSRMLS_CC
        );

        new_object->buffer_zval = old_object->buffer_zval;
        if (new_object->buffer_zval) {
            Z_ADDREF_P(new_object->buffer_zval);
        }

        new_object->buf.as_int8 = old_object->buf.as_int8;
        new_object->offset = old_object->offset;
        new_object->length = old_object->length;
        new_object->type   = old_object->type;

        return new_object_val;
    }

Now that all the formalisms are out of the way, we can start working on the actual functionality: Accessing values at
certain offsets. For that you need two helper functions for getting and setting the offset depending on the type of the
view. This basically just comes down to switching throw all the different types and using the respective member from
the buffer union:

.. code-block:: c

    zval *buffer_view_offset_get(buffer_view_object *intern, size_t offset)
    {
        zval *retval;
        MAKE_STD_ZVAL(retval);

        switch (intern->type) {
            case buffer_view_int8:
                ZVAL_LONG(retval, intern->buf.as_int8[offset]); break;
            case buffer_view_uint8:
                ZVAL_LONG(retval, intern->buf.as_uint8[offset]); break;
            case buffer_view_int16:
                ZVAL_LONG(retval, intern->buf.as_int16[offset]); break;
            case buffer_view_uint16:
                ZVAL_LONG(retval, intern->buf.as_uint16[offset]); break;
            case buffer_view_int32:
                ZVAL_LONG(retval, intern->buf.as_int32[offset]); break;
            case buffer_view_uint32: {
                uint32_t value = intern->buf.as_uint32[offset];
                if (value <= LONG_MAX) {
                    ZVAL_LONG(retval, value);
                } else {
                    ZVAL_DOUBLE(retval, value);
                }
                break;
            }
            case buffer_view_float:
                ZVAL_DOUBLE(retval, intern->buf.as_float[offset]); break;
            case buffer_view_double:
                ZVAL_DOUBLE(retval, intern->buf.as_double[offset]); break;
            default:
                /* Should never happen */
                zend_error_noreturn(E_ERROR, "Invalid buffer view type");
        }

        return retval;
    }

    void buffer_view_offset_set(buffer_view_object *intern, long offset, zval *value)
    {
        if (intern->type == buffer_view_float || intern->type == buffer_view_double) {
            Z_ADDREF_P(value);
            convert_to_double_ex(&value);

            if (intern->type == buffer_view_float) {
                intern->buf.as_float[offset] = Z_DVAL_P(value);
            } else {
                intern->buf.as_double[offset] = Z_DVAL_P(value);
            }

            zval_ptr_dtor(&value);
        } else {
            Z_ADDREF_P(value);
            convert_to_long_ex(&value);

            switch (intern->type) {
                case buffer_view_int8:
                    intern->buf.as_int8[offset] = Z_LVAL_P(value); break;
                case buffer_view_uint8:
                    intern->buf.as_uint8[offset] = Z_LVAL_P(value); break;
                case buffer_view_int16:
                    intern->buf.as_int16[offset] = Z_LVAL_P(value); break;
                case buffer_view_uint16:
                    intern->buf.as_uint16[offset] = Z_LVAL_P(value); break;
                case buffer_view_int32:
                    intern->buf.as_int32[offset] = Z_LVAL_P(value); break;
                case buffer_view_uint32:
                    intern->buf.as_uint32[offset] = Z_LVAL_P(value); break;
                default:
                    /* Should never happen */
                    zend_error(E_ERROR, "Invalid buffer view type");
            }

            zval_ptr_dtor(&value);
        }
    }

Implementing the ``ArrayAccess`` interface is now only matter of doing a bit of bounds checking and dispatching to the
above methods (as well as the usual method boilerplate). Here's how the ``offsetGet`` method could be implemented:

.. code-block:: c

    PHP_FUNCTION(array_buffer_view_offset_get)
    {
        buffer_view_object *intern;
        long offset;
        zval *retval;

        if (zend_parse_parameters(ZEND_NUM_ARGS() TSRMLS_CC, "l", &offset) == FAILURE) {
            return;
        }

        intern = zend_object_store_get_object(getThis() TSRMLS_CC);

        if (offset < 0 || offset >= intern->length) {
            zend_throw_exception(NULL, "Offset is outside the buffer range", 0 TSRMLS_CC);
            return;
        }

        retval = buffer_view_offset_get(intern, offset);
        RETURN_ZVAL(retval, 1, 1);
    }

The remaining three ``offsetSet``, ``offsetExists`` and ``offsetUnset`` methods are pretty much the same, so I'll just
leave them as an exercise to the reader.

The implementation outlined above is about 600 lines of code long and implements the most important parts of
JavaScript's pretty awesome buffer/view system.

But the current implementation does not yet integrate well with PHP. It only implements ``ArrayAccess``, but it can't
be iterated over, can't be counted and so on. Implementing those interactions is what the next section is about.
