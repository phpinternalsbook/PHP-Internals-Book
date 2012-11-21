Custom object storage
=====================

The previous section laid the ground for the creation of simple internal classes. Most of the features described there
should be fairly straightforward because they work the same way as in userland PHP, only expressed more verbosely. This
section on the other hand will go into realms not available to userland classes: The creation and access of custom
object storage.

How are objects created?
------------------------

As a first step lets look at how object are created in PHP. For this the ``object_and_properties_init`` macro or one of
its simpler cousins is used:

.. code-block:: c

    // Create an object of type SomeClass and give it the properties from properties_hashtable
    zval *obj;
    MAKE_STD_ZVAL(obj);
    object_and_properties_init(obj, class_entry_of_SomeClass, properties_hashtable);

    // Create an object of type SomeClass (with the default properties)
    zval *obj;
    MAKE_STD_ZVAL(obj);
    object_init_ex(obj, class_entry_of_SomeClass);
    // = object_and_properties_init(obj, class_entry_of_SomeClass, NULL)

    // Create a default object (stdClass)
    zval *obj;
    MAKE_STD_ZVAL(obj);
    object_init(obj);
    // = object_init_ex(obj, NULL) = object_and_properties_init(obj, NULL, NULL)

In the last case, i.e. when you are creating an ``stdClass`` object you will probably want to add properties afterwards.
This usually isn't done with the ``zend_update_property`` functions from the previous chapter, instead the
``add_property`` macros are used:

.. code-block:: c

    add_property_long(obj, "id", id);
    add_property_string(obj, "name", name, 1); // 1 means the string should be copied
    add_property_bool(obj, "isAdmin", is_admin);
    // also _null(), _double(), _stringl(), _resource() and _zval()

So what does actually happen when an object is created? To find out lets look at the ``_object_and_properties_init``
function:

.. code-block:: c

    ZEND_API int _object_and_properties_init(zval *arg, zend_class_entry *class_type, HashTable *properties ZEND_FILE_LINE_DC TSRMLS_DC) /* {{{ */
    {
        zend_object *object;

        if (class_type->ce_flags & (ZEND_ACC_INTERFACE|ZEND_ACC_IMPLICIT_ABSTRACT_CLASS|ZEND_ACC_EXPLICIT_ABSTRACT_CLASS)) {
            char *what =   (class_type->ce_flags & ZEND_ACC_INTERFACE)                ? "interface"
                         :((class_type->ce_flags & ZEND_ACC_TRAIT) == ZEND_ACC_TRAIT) ? "trait"
                         :                                                              "abstract class";
            zend_error(E_ERROR, "Cannot instantiate %s %s", what, class_type->name);
        }

        zend_update_class_constants(class_type TSRMLS_CC);

        Z_TYPE_P(arg) = IS_OBJECT;
        if (class_type->create_object == NULL) {
            Z_OBJVAL_P(arg) = zend_objects_new(&object, class_type TSRMLS_CC);
            if (properties) {
                object->properties = properties;
                object->properties_table = NULL;
            } else {
                object_properties_init(object, class_type);
            }
        } else {
            Z_OBJVAL_P(arg) = class_type->create_object(class_type TSRMLS_CC);
        }
        return SUCCESS;
    }
    /* }}} */

The function basically does three things: First it verifies that the class can actually be instantiated, then it
resolves the class constants (this is done only on the first instantiation and the details of it aren't important here).
After that comes the important part: The function checks whether the class has  ``create_object`` handler. If it
has one it is called, if it hasn't the default ``zend_objects_new`` implementation is used (and additionally the
properties are initialized).

Here is what ``zend_objects_new`` then does:

.. code-block:: c

    ZEND_API zend_object_value zend_objects_new(zend_object **object, zend_class_entry *class_type TSRMLS_DC)
    {
        zend_object_value retval;

        *object = emalloc(sizeof(zend_object));
        (*object)->ce = class_type;
        (*object)->properties = NULL;
        (*object)->properties_table = NULL;
        (*object)->guards = NULL;
        retval.handle = zend_objects_store_put(*object,
            (zend_objects_store_dtor_t) zend_objects_destroy_object,
            (zend_objects_free_object_storage_t) zend_objects_free_object_storage,
            NULL TSRMLS_CC
        );
        retval.handlers = &std_object_handlers;
        return retval;
    }

The above code contains three interesting things. Firstly the ``zend_object`` structure, which is defined as
follows:

.. code-block:: c

    typedef struct _zend_object {
        zend_class_entry *ce;
        HashTable *properties;
        zval **properties_table;
        HashTable *guards; /* protects from __get/__set ... recursion */
    } zend_object;

This is the "standard" object structure. It contains the class entry used for creation, a properties hashtable, a
properties "table" and a hashtable for recursion guarding. What exactly the difference between ``properties`` and
``properties_table`` is will be covered in a later section of this chapter, at this point you should just know that the
latter is used for properties declared in the class and the former for properties that weren't declared. How the
``guards`` mechanism works will also be covered later.

The ``zend_objects_new`` function allocates the aforementioned standard object structure and initializes it. Afterwards
it calls ``zend_objects_store_put`` to put the object data into the object store. The object store is nothing more than
a dynamically resized array of ``zend_object_store_bucket``s:

.. code-block:: c

    typedef struct _zend_object_store_bucket {
        zend_bool destructor_called;
        zend_bool valid;
        union _store_bucket {
            struct _store_object {
                void *object;
                zend_objects_store_dtor_t dtor;
                zend_objects_free_object_storage_t free_storage;
                zend_objects_store_clone_t clone;
                const zend_object_handlers *handlers;
                zend_uint refcount;
                gc_root_buffer *buffered;
            } obj;
            struct {
                int next;
            } free_list;
        } bucket;
    } zend_object_store_bucket;

The main part here is the ``_store_object`` structure, which contains the stored object in the ``void *object`` member,
followed by three handlers for destruction, freeing and cloning. There is some additional stuff in this structure too,
for example it has its own ``refcount`` property, because one object in the object store can be referenced from several
zvals at the same time and PHP needs to keep track of just how many references there are to be able to free it later.
Additionally the object ``handlers`` are stored too (this is necessary for destruction) and a GC root buffer (how PHPs
cycle collector works will be covered in a later chapter).

Getting back to the ``zend_objects_new`` function, the last thing it does is to set the object ``handlers`` to the
default ``std_object_handlers``.

Overriding create_object
------------------------

When you want to use custom object storage, you will basically repeat the above three steps: First you allocate and
initialize your object, which will contain the standard object as a substructure. Then you put it into the object store
along with several handlers. And lastly you assign your object handlers structure.

In order to do so you have to override the ``create_object`` class handler. Here is a dummy example of how this looks
like (with inline explanations):

.. code-block:: c

    zend_class_entry *test_ce;

    /* We need a (true global) variable to store the object handlers that will be used for our objects. The object
     * handlers are initialized in MINIT. */
    static zend_object_handlers test_object_handlers;

    /* Our custom object structure. It has to contain a `zend_object` value (not a pointer!) as first member, followed
     * by whatever additional properties one may want. */
    typedef struct _test_object {
    	zend_object std;
    	long additional_property;
    } test_object;

    /* This is the handler that will be called when the object is freed. This handler has to destruct the std object
     * (this will free the properties hashtable etc) and also free the object structure itself. (And if there are any
     * other resources that were allocated, those obviously have to be freed here, too.) */
    static void test_free_object_storage_handler(test_object *intern TSRMLS_DC)
    {
    	zend_object_std_dtor(&intern->std TSRMLS_CC);
    	efree(intern);
    }

    /* This is the handler used for creating objects. It takes the class entry (it will also be used for classes that
     * extend this one, that's why the class entry has to be passed in) and returns an object value (which is a handle
     * to the object store and a pointer to the object handlers structure). */
    zend_object_value test_create_object_handler(zend_class_entry *class_type TSRMLS_DC)
    {
    	zend_object_value retval;

        /* Allocate and zero-out the internal object structure. By convention the variable holding the internal
         * structure is usually called `intern`. */
    	test_object *intern = emalloc(sizeof(test_object));
    	memset(intern, 0, sizeof(test_object));

        /* The underlying std zend_object has to be initialized.  */
    	zend_object_std_init(&intern->std, class_type TSRMLS_CC);

    	/* Even if you don't use properties yourself you should still call object_properties_init(), because extending
    	 * classes may use properties. (Generally a lot of the stuff you will do is for the sake of not breaking
    	 * extending classes). */
    	object_properties_init(&intern->std, class_type);

        /* Put the `intern`al object into the object store, with the default dtor handler and our custom free handler.
         * The last NULL parameter is the clone handler, which is left empty for now. */
    	retval.handle = zend_objects_store_put(
    		intern,
    		(zend_objects_store_dtor_t) zend_objects_destroy_object,
    		(zend_objects_free_object_storage_t) test_free_object_storage_handler,
    		NULL TSRMLS_CC
    	);

    	/* Assign the customized object handlers */
    	retval.handlers = &test_object_handlers;

    	return retval;
    }

    /* No methods for now */
    const zend_function_entry test_functions[] = {
    	PHP_FE_END
    };

    PHP_MINIT_FUNCTION(test2)
    {
        /* The usual class registration... */
    	zend_class_entry tmp_ce;
    	INIT_CLASS_ENTRY(tmp_ce, "Test", test_functions);
    	test_ce = zend_register_internal_class(&tmp_ce TSRMLS_CC);

        /* Assign the object creation handler in the class entry */
    	test_ce->create_object = test_create_object_handler;

        /* Initialize the custom object handlers to the default object handlers. Afterwards you normally override
         * individual handlers, but for now lets leave them at the defaults. */
    	memcpy(&test_object_handlers, zend_get_std_object_handlers(), sizeof(zend_object_handlers));

    	return SUCCESS;
    }

The above code isn't particularly useful yet, but it demonstrates the basic structure of pretty much all internal PHP
classes.

Object store handlers
---------------------

As already mentioned above there are three object storage handlers: One for destruction, one for freeing and one for
cloning.

What is a bit confusing at first is that there is both a dtor handler and a free handler, which sounds like they do
about the same thing. The reason is that PHP has a two-phase object destruction system, where first the destructor is
called and then the object is freed. Both phases can happen separately from each other.

In particular this happens with all objects which are still alive when the script ends. For them PHP will first call all
dtor handlers (right after calling any registered shutdown functions), but will only free the objects at a later point
in time, as part of the executor shutdown. This separation of destruction and freeing is necessary to ensure that no
destructors are run during the shutdown sequence, otherwise you could get into situations where userland code is
executed in a half-shutdown environment. Without this separation any ``zval_ptr_dtor`` call during shutdown could blow
up.

Another peculiarity of dtor handlers is that they *aren't* necessarily called. E.g. if a destructor calls ``die`` the
remaining destructors are skipped.

So basically the difference between the two handlers is that dtor can run userland code, but isn't necessarily called,
free on the other hand is always called, but mustn't execute any PHP code. That's why in most cases you will only
specify a custom free handler and use ``zend_objects_destroy_object`` as the dtor handler, which provides the default
behavior of calling ``__destruct`` (if it exists). Once again, even if you don't use ``__destruct`` yourself you should
still specify this handler, otherwise inheriting classes won't be able to use it either.

Now only the clone handler is left. Here the semantics should be straightforward, but the use is a bit more tricky.
This is how such a clone handler might look like:

.. code-block:: c

    static void test_clone_object_storage_handler(test_object *object, test_object **object_clone TSRMLS_DC)
    {
        /* Create a new object */
        test_object *object_clone = emalloc(sizeof(test_object));
        zend_object_std_init(&object_clone->std, object->std.ce TSRMLS_CC);
        object_properties_init(&object_clone->std, object->std.ce);

        /* Do any additional cloning stuff here */
        object_clone->additional_property = object->additional_property;

        /* Return the cloned object */
        *object_clone_target = object_clone;
    }

The clone handler is then passed as the last argument to ``zend_objects_store_put``:

.. code-block:: c

    retval.handle = zend_objects_store_put(
        intern,
        (zend_objects_store_dtor_t) zend_objects_destroy_object,
        (zend_objects_free_object_storage_t) test_free_object_storage_handler,
        (zend_objects_store_clone_t) test_clone_object_storage_handler
        TSRMLS_CC
    );

But this is not yet enough to make the clone handler work: By default the object storage clone handler is simply
ignored. To make it work you have to replace the default clone handler in the object handlers structure with
``zend_objects_store_clone_obj``:

.. code-block:: c

    memcpy(&test_object_handlers, zend_get_std_object_handlers(), sizeof(zend_object_handlers));
    test_object_handler.clone_obj = zend_objects_store_clone_obj;

But overwriting the standard clone handler (``zend_objects_clone_obj``) comes with its own set of problems: Now
properties (as in real properties, not the ones in the custom object storage) won't be copied and also the ``__clone``
method won't be called. That's why most internal classes instead directly specify their own object handler for cloning,
rather than going the extra round through the object storage clone handler. This approach comes with a bit more
boilerplate. For example, this is how the default clone handler looks like:

.. code-block:: c

    ZEND_API zend_object_value zend_objects_clone_obj(zval *zobject TSRMLS_DC)
    {
        zend_object_value new_obj_val;
        zend_object *old_object;
        zend_object *new_object;
        zend_object_handle handle = Z_OBJ_HANDLE_P(zobject);

        /* assume that create isn't overwritten, so when clone depends on the
         * overwritten one then it must itself be overwritten */
        old_object = zend_objects_get_address(zobject TSRMLS_CC);
        new_obj_val = zend_objects_new(&new_object, old_object->ce TSRMLS_CC);

        zend_objects_clone_members(new_object, new_obj_val, old_object, handle TSRMLS_CC);

        return new_obj_val;
    }

This function first fetches the ``zend_object*`` structure from the object store using ``zend_objects_get_address``,
then creates a new object with the same class entry (using ``zend_objects_new``) and then calls
``zend_objects_clone_members``, which will (as the name says) clone the properties, but will also call the ``__clone``
method if it exists.

A custom object cloning handler looks similar, with the main difference being that instead of calling
``zend_objects_new`` we'll rather call our ``create_object`` handler:

.. code-block:: c

    static zend_object_value test_clone_handler(zval *object TSRMLS_DC)
    {
        /* Get the internal structure of the old object */
        test_object *old_object = zend_object_store_get_object(object TSRMLS_CC);

        /* Create a new object with the same class entry. This will only give us back the zend_object_value, but
         * not the actual internal structure of the new object. */
        zend_object_value new_object_val = test_create_object_handler(Z_OBJCE_P(object) TSRMLS_CC);

        /* To get the internal structure we need to fetch it from the object store using the handle we got from
         * the create_object handler. */
        test_object *new_object = zend_object_store_get_object_by_handle(new_object_val.handle TSRMLS_CC);

        /* Clone properties and call __clone */
        zend_objects_clone_members(
            &new_object->std, new_object_val,
            &old_object->std, Z_OBJ_HANDLE_P(object) TSRMLS_CC
        );

        /* Here comes the actual custom cloning code */
        new_object->additional_property = old_object->additional_property;

        return new_object_val;
    }

Interacting with the object store
---------------------------------

In the above code samples you have already seen several functions for interacting with the object store. The first one
was ``zend_objects_store_put``, which is used for inserting objects into the store. Also three functions for getting
objects back from the store were mentioned:

``zend_object_store_get_object_by_handle()``, as the name already says, gets an object from the store given its handle.
This function is used when you have an object handle, but don't have the associated zval (like in the clone handler).
In most other cases on the other hand you'll use the ``zend_object_store_get_object()`` function which accepts a zval
and will extract the handle from it.

The third getter function that was used is ``zend_objects_get_address()``, which does the exact same thing as
``zend_object_store_get_object()``, but returns the result as a ``zend_object*`` rather than a ``void*``. As such this
function is pretty useless because C allows implicit casts from ``void*`` to other pointer types.

The most important of these functions is ``zend_object_store_get_object()``. You will be using it a lot. Pretty much
all methods will look similar to this:

.. code-block:: c

    PHP_METHOD(Test, foo)
    {
        zval *object;
        test_object *intern;

        if (zend_parse_parameters_none() == FAILURE) {
            return;
        }

        object = getThis();
        intern = zend_object_store_get_object(object TSRMLS_CC);

        /* Do some stuff here, like returning an internal property: */
        RETURN_LONG(intern->additional_property);
    }

There are some more functions provided by the object store, e.g. for managing the object refcount, but those are rarely
used directly, so they aren't covered here.