Symtable and array API
----------------------

The hashtable API allows you to work with values of any type, but in the vast majority of cases the values will be
zvals. Using the ``zend_hash`` API with zvals can often be somewhat cumbersome, as you need to handle zval allocation
and initialization yourself. This is why PHP provides a second set of APIs specifically aimed at this use case.

Symtables
---------

.. todo::

    ZEND_INIT_SYMTABLE
    ZEND_INIT_SYMTABLE_EX

    zend_symtable_update
    zend_symtable_del
    zend_symtable_find
    zend_symtable_exists
    zend_symtable_update_current_key_ex

    array_init
    array_init_size

    add_assoc_*_ex
    add_assoc_*
    add_index_*
    add_next_index_*
    add_get_assoc_stringl?(_ex)?
    add_get_index_*_(long|double|stringl?)

    array_set_zval_key (?)

    null
    bool
    long
    double
    string
    stringl
    resource
    zval

As you can see, it's a little bit weird to insert zvals into a hashtable. Fortunately, there exists another API witch
goal is to create and allocate the zval for us, just pass its value and you are done. What is special about this API,
is that it doesn't play directly with a hashtable itself, but expect you to embed the Hashtable into a zval as well. The
API is so fully zval-turned, but under the hood it uses zend_hash API. Playing with the zval special API, our above
example then become something like that::

    zval *ht1 = NULL;
    ALLOC_INIT_ZVAL(ht1);
    array_init(ht1, 3);

    if (add_index_long(ht1, 12, 42) == SUCCESS) {
        php_printf("Added zval of type long (42) to ht1 at index 12\n");
    }

    if (add_assoc_string(ht1, "str", "hello world", 1) == SUCCESS) {
        php_printf("Added zval of type string ('hello world') to ht1 at index 'str' \n");
    }

    /* There does not exist something like add_next_index_bool() */

.. note:: Like we said, the API is different weither the key you provide is an integer (``ulong``), or a string
   (``char *``) or if you dont provide key at all and let the implementation choose the next one for you. Mainly
   "*assoc*" means string keys, and "*index*" means integer keys.

So, depending on the case, you'll choose to use directly the zend_hash API, or go with the zval ``add_`` API.

...