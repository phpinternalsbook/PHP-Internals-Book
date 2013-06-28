Iterators
=========

In the last section we implemented a few object handlers to improve integration of typed arrays into the language. One
aspect is still missing though: Iteration. In this section we'll look at how iterators are implemented internally and
how we can make use of them. Once again typed arrays will serve as the example.

The ``get_iterator`` handler
----------------------------

Internally iteration works very similar to the userland ``IteratorAggregate`` interface. The class has a
``get_iterator`` handler that returns a ``zend_object_iterator*``, which looks as follows::

    struct _zend_object_iterator {
        void *data;
        zend_object_iterator_funcs *funcs;
        ulong index; /* private to fe_reset/fe_fetch opcodes */
    };

The ``index`` member is used internally by the ``foreach`` implementation. It is incremented on each iteration and is
used for the keys if you don't specify a custom key function. The ``funcs`` member contains handlers for the different
iteration actions::

    typedef struct _zend_object_iterator_funcs {
        /* release all resources associated with this iterator instance */
        void (*dtor)(zend_object_iterator *iter TSRMLS_DC);

        /* check for end of iteration (FAILURE or SUCCESS if data is valid) */
        int (*valid)(zend_object_iterator *iter TSRMLS_DC);

        /* fetch the item data for the current element */
        void (*get_current_data)(zend_object_iterator *iter, zval ***data TSRMLS_DC);

        /* fetch the key for the current element (optional, may be NULL) */
        void (*get_current_key)(zend_object_iterator *iter, zval *key TSRMLS_DC);

        /* step forwards to next element */
        void (*move_forward)(zend_object_iterator *iter TSRMLS_DC);

        /* rewind to start of data (optional, may be NULL) */
        void (*rewind)(zend_object_iterator *iter TSRMLS_DC);

        /* invalidate current value/key (optional, may be NULL) */
        void (*invalidate_current)(zend_object_iterator *iter TSRMLS_DC);
    } zend_object_iterator_funcs;

The handlers are pretty similar to the ``Iterator`` interface, only with slightly different names. The only handler
that has no correspondence in userland is ``invalidate_current``, which can be used to destroy the current key/value.
The handler is largely unused though, in particular ``foreach`` won't even call it.

The last member in the struct is ``data``, which can be used to carry around some custom data. Usually this one slot
isn't enough though, so instead of the structure is extended, similarly to what you have already seen with
``zend_object``.

In order to iterate typed arrays we'll have to store a few things: First of all, we need to hold a reference to the
buffer view object (otherwise it may be destroyed during iteration). We can store this in the ``data`` member.
Furthermore we should keep around the ``buffer_view_object`` so we don't have to refetch it on every handler call.
Additionally we'll have to store the current iteration ``offset`` and the ``zval*`` of the current element (you'll see
a bit later why we need to do this)::

    typedef struct _buffer_view_iterator {
        zend_object_iterator intern;
        buffer_view_object *view;
        size_t offset;
        zval *current;
    } buffer_view_iterator;

Lets also declare a dummy ``zend_object_iterator_funcs`` structure so we have something to work on::

    static zend_object_iterator_funcs buffer_view_iterator_funcs = {
        buffer_view_iterator_dtor,
        buffer_view_iterator_valid,
        buffer_view_iterator_get_current_data,
        buffer_view_iterator_get_current_key,
        buffer_view_iterator_move_forward,
        buffer_view_iterator_rewind
    };

Now we can implement the ``get_iterator`` handler. This handler receives the class entry, the object and whether the
iteration is done by reference and returns a ``zend_object_iterator*``. All we have to do is allocate the iterator and
set the respective members::

    zend_object_iterator *buffer_view_get_iterator(
        zend_class_entry *ce, zval *object, int by_ref TSRMLS_DC
    ) {
        buffer_view_iterator *iter;

        if (by_ref) {
            zend_throw_exception(NULL, "Cannot iterate buffer view by reference", 0 TSRMLS_CC);
            return NULL;
        }

        iter = emalloc(sizeof(buffer_view_iterator));
        iter->intern.funcs = &buffer_view_iterator_funcs;

        iter->intern.data = object;
        Z_ADDREF_P(object);

        iter->view = zend_object_store_get_object(object TSRMLS_CC);
        iter->offset = 0;
        iter->current = NULL;

        return (zend_object_iterator *) iter;
    }

Finally we have to adjust the macro for registering buffer view classes::

    #define DEFINE_ARRAY_BUFFER_VIEW_CLASS(class_name, type)                     \
        INIT_CLASS_ENTRY(tmp_ce, #class_name, array_buffer_view_functions);      \
        type##_array_ce = zend_register_internal_class(&tmp_ce TSRMLS_CC);       \
        type##_array_ce->create_object = array_buffer_view_create_object;        \
        type##_array_ce->get_iterator = buffer_view_get_iterator;                \
        type##_array_ce->iterator_funcs.funcs = &buffer_view_iterator_funcs;     \
        zend_class_implements(type##_array_ce TSRMLS_CC, 2,                      \
            zend_ce_arrayaccess, zend_ce_traversable);

The new things are the assignment to the ``get_iterator`` and ``iterator_funcs.funcs`` as well as the implementation
of the ``Traversable`` interface.

Iterator functions
------------------

Now lets actually implement the ``buffer_view_iterator_funcs`` that we specified above::

    static void buffer_view_iterator_dtor(zend_object_iterator *intern TSRMLS_DC)
    {
        buffer_view_iterator *iter = (buffer_view_iterator *) intern;

        if (iter->current) {
            zval_ptr_dtor(&iter->current);
        }

        zval_ptr_dtor((zval **) &intern->data);
        efree(iter);
    }

    static int buffer_view_iterator_valid(zend_object_iterator *intern TSRMLS_DC)
    {
        buffer_view_iterator *iter = (buffer_view_iterator *) intern;

        return iter->offset < iter->view->length ? SUCCESS : FAILURE;
    }

    static void buffer_view_iterator_get_current_data(
        zend_object_iterator *intern, zval ***data TSRMLS_DC
    ) {
        buffer_view_iterator *iter = (buffer_view_iterator *) intern;

        if (iter->current) {
            zval_ptr_dtor(&iter->current);
        }

        if (iter->offset < iter->view->length) {
            iter->current = buffer_view_offset_get(iter->view, iter->offset);
            *data = &iter->current;
        } else {
            *data = NULL;
        }
    }

    #if ZEND_MODULE_API_NO >= 20121212
    static void buffer_view_iterator_get_current_key(
        zend_object_iterator *intern, zval *key TSRMLS_DC
    ) {
        buffer_view_iterator *iter = (buffer_view_iterator *) intern;
        ZVAL_LONG(key, iter->offset);
    }
    #else
    static int buffer_view_iterator_get_current_key(
        zend_object_iterator *intern, char **str_key, uint *str_key_len, ulong *int_key TSRMLS_DC
    ) {
        buffer_view_iterator *iter = (buffer_view_iterator *) intern;

        *int_key = (ulong) iter->offset;
        return HASH_KEY_IS_LONG;
    }
    #endif

    static void buffer_view_iterator_move_forward(zend_object_iterator *intern TSRMLS_DC)
    {
        buffer_view_iterator *iter = (buffer_view_iterator *) intern;

        iter->offset++;
    }

    static void buffer_view_iterator_rewind(zend_object_iterator *intern TSRMLS_DC)
    {
        buffer_view_iterator *iter = (buffer_view_iterator *) iter;

        iter->offset = 0;
        iter->current = NULL;
    }

The functions should be rather straightforward, so only a few comments:

``get_current_data`` gets a ``zval*** data`` as the parameter and expects us to write a ``zval**`` into it using
``*data = ...``. The ``zval**`` is required because iteration can also happen by reference, in which case ``zval*``
won't suffice. The ``zval**`` is the reason why we have to store the current ``zval*`` in the iterator.

How the ``get_current_key`` handler looks like depends on the PHP version: With PHP 5.5 you simply have to write the
key into the passed ``key`` variable using one of the ``ZVAL_*`` macros.

On older versions of PHP the ``get_current_key`` handler takes three parameters that can be set depending on which key
type is returned. If you return ``HASH_KEY_NON_EXISTANT`` the resulting key will be ``null`` and you don't have to set
any of them. For ``HASH_KEY_IS_LONG`` you set the ``int_key`` argument. For ``HASH_KEY_IS_STRING`` you have to set
``str_key`` and ``str_key_len``. Note that here ``str_key_len`` is the string length plus one (similar to how it is done
in the ``zend_hash`` APIs).

Honoring inheritance
--------------------

Once again we need to consider what happens when the user extends the class and wants to change the iteration behavior.
Right now he would have to reimplement the iteration mechanism manually, because the individual iteration handlers are
not exposed to userland (only through foreach).

As already with the object handlers we'll solve this by also implementing the normal ``Iterator`` interface. This time
we won't need special handling to ensure that PHP actually calls the overridden methods: PHP will automatically use the
fast internal handlers when the class is used directly, but will use the ``Iterator`` methods if the class is extended.

In order to implement the ``Iterator`` methods we have to add a new ``size_t current_offset`` member to
``buffer_view_object``, which stores the current offset for the iteration methods (and is completely separate from the
iteration state used by ``get_iterator``-style iterators). The methods itself are to the most part just argument
checking boilerplate::

    PHP_FUNCTION(array_buffer_view_rewind)
    {
        buffer_view_object *intern;

        if (zend_parse_parameters_none() == FAILURE) {
            return;
        }

        intern = zend_object_store_get_object(getThis() TSRMLS_CC);
        intern->current_offset = 0;
    }

    PHP_FUNCTION(array_buffer_view_next)
    {
        buffer_view_object *intern;

        if (zend_parse_parameters_none() == FAILURE) {
            return;
        }

        intern = zend_object_store_get_object(getThis() TSRMLS_CC);
        intern->current_offset++;
    }

    PHP_FUNCTION(array_buffer_view_valid)
    {
        buffer_view_object *intern;

        if (zend_parse_parameters_none() == FAILURE) {
            return;
        }

        intern = zend_object_store_get_object(getThis() TSRMLS_CC);
        RETURN_BOOL(intern->current_offset < intern->length);
    }

    PHP_FUNCTION(array_buffer_view_key)
    {
        buffer_view_object *intern;

        if (zend_parse_parameters_none() == FAILURE) {
            return;
        }

        intern = zend_object_store_get_object(getThis() TSRMLS_CC);
        RETURN_LONG((long) intern->current_offset);
    }

    PHP_FUNCTION(array_buffer_view_current)
    {
        buffer_view_object *intern;
        zval *value;

        if (zend_parse_parameters_none() == FAILURE) {
            return;
        }

        intern = zend_object_store_get_object(getThis() TSRMLS_CC);
        value = buffer_view_offset_get(intern, intern->current_offset);
        RETURN_ZVAL(value, 1, 1);
    }

    /* ... */

    ZEND_BEGIN_ARG_INFO_EX(arginfo_buffer_view_void, 0, 0, 0)
    ZEND_END_ARG_INFO()

    /* ... */

    PHP_ME_MAPPING(rewind, array_buffer_view_rewind, arginfo_buffer_view_void, ZEND_ACC_PUBLIC)
    PHP_ME_MAPPING(next, array_buffer_view_next, arginfo_buffer_view_void, ZEND_ACC_PUBLIC)
    PHP_ME_MAPPING(valid, array_buffer_view_valid, arginfo_buffer_view_void, ZEND_ACC_PUBLIC)
    PHP_ME_MAPPING(key, array_buffer_view_key, arginfo_buffer_view_void, ZEND_ACC_PUBLIC)
    PHP_ME_MAPPING(current, array_buffer_view_current, arginfo_buffer_view_void, ZEND_ACC_PUBLIC)

Obviously we now should also implement ``Iterator`` rather than ``Traversable``::

    #define DEFINE_ARRAY_BUFFER_VIEW_CLASS(class_name, type)                     \
        INIT_CLASS_ENTRY(tmp_ce, #class_name, array_buffer_view_functions);      \
        type##_array_ce = zend_register_internal_class(&tmp_ce TSRMLS_CC);       \
        type##_array_ce->create_object = array_buffer_view_create_object;        \
        type##_array_ce->get_iterator = buffer_view_get_iterator;                \
        type##_array_ce->iterator_funcs.funcs = &buffer_view_iterator_funcs;     \
        zend_class_implements(type##_array_ce TSRMLS_CC, 2,                      \
            zend_ce_arrayaccess, zend_ce_iterator);

One last consideration regarding this: In general it is always better to implement ``IteratorAggregate`` rather than
``Iterator``, because ``IteratorAggregate`` decouples the iterator state from the main object. This is obviously simply
better design, but also allows things like independent nested iteration. I still chose to implement ``Iterator`` here,
because aggregates have a higher implementational overhead (as they require a separate class that has to interact with
an independent object).