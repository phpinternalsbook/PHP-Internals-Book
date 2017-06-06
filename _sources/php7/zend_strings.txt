Strings management : zend_string
================================

Any program needs to manage strings. Here, we'll detail the zend_string structure which helps for that.
Every time PHP needs to work with a string, a zend_string structure will be used. This structure is just a simple
thin wrapper over the char * string type of the C language.

It adds memory management facilities, so that a same string can be shared in several places without the need to 
duplicate it. Also, some strings are "interned", that is they are "persistent" allocated and specialy managed by the 
memory manager so that they don't get destroyed across several requests.

Structure and access macros
---------------------------

Here is the simple zend_string structure explosed::

    struct _zend_string {
	    zend_refcounted_h gc;
	    zend_ulong        h;
	    size_t            len;
	    char              val[1];
    };

Like you can see, the structure embeds a ``zend_refcounted_h`` header. This is done for memory management and reference
counting, as you may have learnt by reading the :doc:`php7/memory_management` chapter.
As the string is very likely to be used as the key of a HashTable probe, it embeds its hash in the ``h`` field. This is 
an unsigned long ``zend_ulong``. This number is only used when the ``zend_string`` needs to be hashed, aka especially 
when used together with :doc:`/php7/hashtables`; this is very likely though.

As you know, the string knows its length as the ``len`` field, to support "binary strings". Binary strings are 
strings that embeds one or several ``NUL`` characters (\\0). When passed to libc functions, those strings will get 
truncated or their length won't be computed the right way. So in ``zend_string``, the length of the string is always 
known. Please, note that the length computes the number of ASCII chars (bytes) not counting the terminating ``NUL``, but 
counting the eventual middle NULs. For example, the string "foo" is stored as "foo\\0" in a ``zend_string`` and its 
length is then 3. Also, the string "foo\\0bar" will be stored as "foo\\0bar\\0" and the length will be 7.

Finally, the characters are stored into the ``char[1]`` field. This is not a ``char *``, but a ``char[1]``. Why that ? 
This is a memory optimization known as "C struct hack" (you may use a search engine with these terms). Basically, that 
allows the engine to allocate space for the ``zend_string`` structure and the charcaters to be stored, as one solo C 
pointer. This optimizes memory accesses as memory will be a contiguous allocated block, and not two blocks sparsed in 
memory (one for ``zend_string *``, and one for the ``char *`` to store into it).

This struct hack must be remembered, as the memory layout looks like with the C chars at the end of the C ``zend_string`` 
structure, and may be felt/seen when using a C debugger (or when debugging strings). This hack is entirely managed by 
the API you'll use when manipulating ``zend_string`` structures.

Using zend_string API
---------------------

Simple use case
***************

Like with :doc:`/php7/zvals`, you dont manipulate the ``zend_string`` internals fields by hand, but always use macros 
for that. There also exists macros to trigger actions on strings. Those are not functions but macros, all stored into 
the required ``Zend/zend_string.h`` header::

    zend_string *str;
    
    str = zend_string_init("foo", strlen("foo"), 0);
    php_printf("This is my string: %s\n", ZSTR_VAL(str));
    php_printf("It is %zd char long\n", ZSTR_LEN(str));

    zend_string_release(str);

The above simple example show you basic string management. The ``zend_string_init()`` function (which in fact is a macro, 
but let's pass such details) should be given your full C string as a ``char *``, and its length. The last parameter- of 
type int- should be 0 or 1.
If you pass 0, you ask the engine to use a request-bound heap allocation using the Zend Memory Manager. Such allocation 
will be destroyed at the end of the current request. If you don't do it yourself, on a debug build, the engine will 
shout at you about a memory leak you just created.
If you pass 1, you ask for what we called a "persistent" allocation, that is the engine will use a traditionnal C 
``malloc()`` call and will not track the memory allocation in any way.

Then, we display the string. We access the character array by using the ``ZSTR_VAL()`` macro. ``ZSTR_LEN()`` allows 
access to the length informations. Like with zvals, you always use macros to access the structure fields and don't do 
that by hand yourself. zend_string related macros all start with ``ZSTR_**()``, beware that is not the same as 
``Z_STR**()`` macros.

.. note:: The length is stored using a ``size_t`` type. Hence, to display it, "%zd" is necessary for printf(). You 
          should always use the right printf() formats. Failing to do that can crash the application or create security 
          issues. For a nice recall on printf() formats, please visit 
          `this link <http://www.cplusplus.com/reference/cstdio/printf/>`_

Finally, we release the string using ``zend_string_release()``. This release is mandatory. This is about memory management.
The "releasing" is a simple operation : decrement the reference counter of the string, if it falls to zero, the API will 
free the string for you. If you forget to release a string, you will very likely create a memory leak.

.. note:: You must always think about memory management in C. If you allocate - whether directly using malloc(), or
          using an API that will do it for you - you must free at some point. Failing to do that will create memory 
          leaks and translate into a badly designed program that nobody will be able to use safely.

Playing with the hash
*********************

If you need to access the hash, use ``ZSTR_H()``. However, the hash is not computed automatically when you create your 
``zend_string``. It will be done for you however when using that string with the HashTable API.
If you want to force the hash to get computed now, use ``ZSTR_HASH()`` or ``zend_string_hash_val()``.
Once the hash is computed, it is saved and never computed again. If for any reason, you need to recompute it - f.e 
because you changed the value of the string - use ``zend_string_forget_hash_val()``::

    zend_string *str;

    str = zend_string_init("foo", strlen("foo"), 0);
    php_printf("This is my string: %s\n", ZSTR_VAL(str));
    php_printf("It is %zd char long\n", ZSTR_LEN(str));
    
    zend_string_hash_val(str);
    php_printf("The string hash is %lu\n", ZSTR_H(str));

    zend_string_forget_hash_val(str);
    php_printf("The string hash is now cleared back to 0!");

    zend_string_release(str);

String copy and memory management
*********************************

One very nice feature of ``zend_string`` API is that it allows one part to "own" a string by simply declaring interest 
with it. The engine will then not duplicate the string in memory, but simply increment its refcount 
(as part of its zend_refcounted_h). This allows sharing a single piece of memory in many places into the code.

That way, when we talk about "copying" a ``zend_string``, in fact we don't copy anything in memory. If needed- that is 
still a possible operation- we then talk about "duplicating" the string. Here we go::

    zend_string *foo, *bar, *bar2, *baz;

    foo = zend_string_init("foo", strlen("foo"), 0); /* creates the "foo" string in foo */
    bar = zend_string_init("bar", strlen("bar"), 0); /* creates the "bar" string in bar */
    
    /* creates bar2 and shares the "bar" string from bar into bar2.
       Also increments the refcount of the "bar" string to 2 */
    bar2 = zend_string_copy(bar); 

    php_printf("We just copied two strings\n");
    php_printf("See : bar content : %s, bar2 content : %s\n", ZSTR_VAL(bar), ZSTR_VAL(bar2));
    
    /* Duplicate in memory the "bar" string, create the baz variable and
       make it solo owner of the newly created "bar" string */
    baz = zend_string_dup(bar, 0);
    
    php_printf("We just duplicated 'bar' in 'baz'\n");
    php_printf("Now we are free to change 'baz' without fearing to change 'bar'\n");
    
    /* Change the last char of the second "bar" string
       turning it to "baz" */
    ZSTR_VAL(baz)[ZSTR_LEN(baz) - 1] = 'z';
    
    /* Forget the old hash (if computed) as now the string changed, thus
       its hash must also change and get recomputed */
    zend_string_forget_hash_val(baz);
    
    php_printf("'baz' content is now %s\n", ZSTR_VAL(baz));

    zend_string_release(foo);  /* destroys (frees) the "foo" string */
    zend_string_release(bar);  /* decrements the refcount of the "bar" string to one */
    zend_string_release(bar2); /* destroys (frees) the "bar" string both in bar and bar2 vars */
    zend_string_release(baz);  /* destroys (frees) the "baz" string */
    
We start by just allocating "foo" and "bar". Then we create the ``bar2`` string as being a copy of ``bar``. Here, everybody 
must remember : ``bar`` and ``bar2`` point to *the same* C string in memory, and changing one will change the second 
one. This is ``zend_string_copy()`` behavior : it just increments the refcount of the owned C string.

If we want to separate the strings- aka we want to have two different copies of that string in memory -we need to 
duplicate using ``zend_string_dup()``. We then duplicate ``bar2`` variable string into the ``baz`` variable. Now, the 
``baz`` variable embeds its own copy of the string, and can change it without impacting ``bar2``. That is what we do : 
we change the final 'r' in 'bar' with a 'z', for 'baz'. And then we display it, and free memory of every string.

Note that we forgot the hash value (if it were computed before, no need to think about that detail). This is a good 
practice to remember about. Like we already said, the hash is used if the ``zend_string`` is used as part of HashTables.
This is a very common operation in development, and changing a string value requires to recompute the hash value as 
well. Forgetting such a step will lead to bugs that could cost some time to track.

String operations
*****************

The ``zend_string`` API allows other operations, such as extending or shrinking strings, changing their case or comparing
them. There is no concat operation available yet, but that is pretty easy to perform::

    zend_string *foo, *bar, *foobar, *lc;

    foo = zend_string_init("FOO", strlen("FOO"), 0);
    bar = zend_string_init("bar", strlen("bar"), 0);

    /* Compares a zend_string against a C string litteral */
    if (!zend_string_equals_literal(foo, "foobar")) {
    	foobar = zend_string_copy(foo);

    	/* realloc()ates the C string to a larger buffer */
    	foobar = zend_string_extend(foobar, strlen("foobar"), 0);

        /* concatenates "bar" after the newly reallocated large enough "foo" */
    	memcpy(ZSTR_VAL(foobar) + ZSTR_LEN(foo), ZSTR_VAL(bar), ZSTR_LEN(bar));
    }

    php_printf("This is my new string: %s\n", ZSTR_VAL(foobar));

    /* Compares two zend_string together */
    if (!zend_string_equals(foo, foobar)) {
        /* duplicates a string and lowers it */
    	lc = zend_string_tolower(foobar);
    }

    php_printf("This is in LC: %s\n", ZSTR_VAL(lc));

    /* frees memory */
    zend_string_release(foo);
    zend_string_release(bar);
    zend_string_release(foobar);
    zend_string_release(lc);

zend_string access with zvals
*****************************

Now that you know how to manage and manipulate zend_string , let's see the interaction they got with zvals.
You need to be familiar with zvals, if not, read the :doc:`/php7/zvals` dedicated chapter.

The macros will allow you to store a ``zend_string`` into a ``zval``, or to read the ``zend_string`` from a ``zval``::

    zval myval;
    zend_string *hello, *world;
    
    zend_string_init(hello, "hello", strlen("hello"), 0);
    
    /* Stores the string into the zval */
    ZVAL_STR(&myval, hello);
    
    /* Reads the C string, from the zend_string from the zval */
    php_printf("The string is %s", Z_STRVAL(myval));
    
    zend_string_init(world, "world", strlen("world"), 0);
    
    /* Changes the zend_string into myval : replaces it by another one */
    Z_STR(myval) = world;

What you must memorize is that every macro beginning by ``ZSTR_***(s)`` will act on a ``zend_string``.

* ``ZSTR_VAL()``
* ``ZSTR_LEN()``
* ``ZSTR_HASH()``
* ...

Every macro beginning by ``Z_STR**(z)`` will act on a ``zend_string`` itself embeded into a ``zval``

* ``Z_STRVAL()`` 
* ``Z_STRLEN()`` 
* ``Z_STRHASH()``
* ...

A few other that you won't probably need also exist.

Classical C strings
*******************

Just a quick note about classical C strings. In C, strings are character arrays (``char foo[]``), or pointers to 
characters (``char *``). They don't know anything about their length, that's why they are NUL terminated (knowing the
beginning of the string and its end, you know its length).

Before PHP 7, ``zend_string`` structure simply did not exist. A traditionnal ``char * / int`` couple were used back in 
that time. You may still find rare places into PHP where ``char * / int`` couple is used instead of ``zend_string``. 
You may also find API facilities to interact between a ``zend_string`` on one side, and a ``char * / int`` couple on 
the other side.

Whereever it is possible : make use of ``zend_string``.

Interned zend_string
********************

