Symtables and array API
-----------------------

...

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