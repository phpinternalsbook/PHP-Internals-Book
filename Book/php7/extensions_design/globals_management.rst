Managing global state
=====================

There is always a need of some global space in imperative languages. While programming PHP or extensions, we will make
a clear distinction between what we call request-bound globals, and true globals.

Request globals are global variables you need to carry-and-memorize information as you are in the process of treating a
request. A simple example is that you ask the user to provide a value in a function argument, and you want to be able to
use it back in other functions. Beside the fact that this piece of information "keeps its value" across several PHP
function calls, it only keeps that value for the current request. The next-to-come request should know nothing about it.
PHP provides a mechanism to manage requests globals whatever the multi-processing model that were chosen, and we will
detail that later in this chapter.

True globals are piece of information that remain across requests. Those information are usually read-only. If you
need to write to such globals as part of request treatment then PHP can't help you.
If you use :doc:`threads as multi-processing model <php_lifecycle>`, you'll need to perform memory locks on your side.
If you use :doc:`processes as multi-processing model <php_lifecycle>`, you'll need to use your own IPC (Inter Process
Communication) on your side.
Such cases should however never happen in PHP extensions programming.

Managing request globals
************************

Here is a simple example of a simple extension using a request global::

    /* true C global */
    static zend_long rnd = 0;

    static void pib_rnd_init(void)
    {
        /* Pick a number to guess between 0 and 100 */
        php_random_int(0, 100, &rnd, 0);
    }

    PHP_RINIT_FUNCTION(pib)
    {
        pib_rnd_init();

        return SUCCESS;
    }

    PHP_FUNCTION(pib_guess)
    {
        zend_long r;

        if (zend_parse_parameters(ZEND_NUM_ARGS(), "l", &r) == FAILURE) {
            return;
        }

        if (r == rnd) {
            /* Reset the number to guess */
            pib_rnd_init();
            RETURN_TRUE;
        }

        if (r < rnd) {
            RETURN_STRING("more");
        }

        RETURN_STRING("less");
    }

    PHP_FUNCTION(pib_reset)
    {
        if (zend_parse_parameters_none() == FAILURE) {
            return;
        }

        pib_rnd_init();
    }

Like you can see, this extension picks a random integer when a request starts, and then the user - through
``pib_guess()`` - can try to guess the number. Once guessed, the number resets. If the user wants to, he could also
call ``pib_reset()`` to reset the number himself by hand.

That random number has been implemented as **a true C global variable**. While this is not a problem if PHP is used in
processes as part of the :doc:`multi-processing model <php_lifecycle>`; **this is a no-go** if that later uses threads.

.. note:: :doc:`As a reminder <php_lifecycle>`, you don't master what multi-processing model will be used. You must be
          prepared to both models when you design extensions.

When threads are used, such a true C global is shared against every thread of the server. For our above example, what
will happen is that every parallel user of the webserver will share the same number. Some could reset the number
in-a-go as others would try to guess it. In short, you clearly understand here the crucial problem with threads.

We need to persist one piece of data into the same request, but we need to have it **bound** to the current request,
even if the multi-processing model PHP is run into makes use of threads.

Using TSRM macros to protect global space
-----------------------------------------

PHP designed a layer that helps the extension and Core developers to deal with request-globals. That layer is called
**TSRM** (Thread Safe Resource Manager) and is exposed as a set of macros you must use any-time you need to access a
request-bound global (read and write access).

Behind the scene, those macros will resolve to something like the code we showed above in the case that the
multi-processing model uses processes. Like we saw, the above code is perfectly valid if no threads are used. So, when
processes will be used, the macros we'll see in a minute will expand to something similar.

What you need to do first is to declare a structure that will be the root of all your globals::

    ZEND_BEGIN_MODULE_GLOBALS(pib)
        zend_long rnd;
    ZEND_END_MODULE_GLOBALS(pib)

    /* Resolved as :
    *
    * typedef struct _zend_pib_globals {
    *    zend_long rnd;
    * } zend_pib_globals;
    */

Then, you create a true global variable of such a type::

    ZEND_DECLARE_MODULE_GLOBALS(pib)

    /* Resolved as zend_pib_globals pib_globals; */

Now, you may access your data using global macro accessor. This later macro has been created by the
:doc:`skeleton <extension_skeleton>`, it should be defined in your *php_pib.h* header file. Here is what it looks like::

    #ifdef ZTS
    #define PIB_G(v) ZEND_MODULE_GLOBALS_ACCESSOR(pib, v)
    #else
    #define PIB_G(v) (pib_globals.v)
    #endif

Like you can see, if ZTS mode is not enabled, that is if you
:doc:`compiled PHP and the extension with no Thread safety <../build_system/building_php>` (we call that mode *NTS* :
Non-Thread-Safe), the macro simply resolves to the data declared into your structure. Hence the following changes::

    static void pib_rnd_init(void)
    {
        php_random_int(0, 100, &PIB_G(rnd), 0);
    }

    PHP_FUNCTION(pib_guess)
    {
        zend_long r;

        if (zend_parse_parameters(ZEND_NUM_ARGS(), "l", &r) == FAILURE) {
            return;
        }

        if (r == PIB_G(rnd)) {
            pib_rnd_init();
            RETURN_TRUE;
        }

        if (r < PIB_G(rnd)) {
            RETURN_STRING("more");
        }

        RETURN_STRING("less");
    }

.. note:: When using a process model, the *TSRM* macros simply resolve to an access to a true C global variable.

Things get a lot more complicated when threads are used, that is when you
:doc:`compile PHP with ZTS <../build_system/building_php>`. All the macros we saw then resolve to something totaly
different and a bit hard to explain here. Basically, what happens is that *TSRM* does a hard job using TLS
(Thread Local Storage) when compiled with ZTS.

.. note:: In a word, when compiled in ZTS, the globals will be bound to the current thread, whereas when compiled in
          NTS, the globals will be bound to the current process. The TSRM macros take care of the hard job.
          You may be interested in how things work, `then browse the /TSRM directory <https://github.com/php/php-src/
          tree/d0b7eed0c9d873a0606dbbc7e33f14492f1a3dd6/TSRM>`_ of PHP source code to learn more about Thread Safety
          into PHP.

Using globals hooks in extensions
---------------------------------

Sometimes, it may happen that you need your globals to be initialized to some default value, usually zero. The TSRM
system helped by the engine provides a hook to give your globals default values, we call it **GINIT**.

.. note:: For a full view of PHP hooks, refer to the :doc:`PHP lifecycle chapter <php_lifecycle>`.

Let's zero our random value::

    PHP_GSHUTDOWN_FUNCTION(pib)
    { }

    PHP_GINIT_FUNCTION(pib)
    {
        pib_globals->rnd = 0;
    }

    zend_module_entry pib_module_entry = {
        STANDARD_MODULE_HEADER,
        "pib",
        NULL,
        NULL,
        NULL,
        NULL,
        NULL,
        NULL,
        "0.1",
        PHP_MODULE_GLOBALS(pib),
        PHP_GINIT(pib),
        PHP_GSHUTDOWN(pib),
        NULL, /* PRSHUTDOWN() */
        STANDARD_MODULE_PROPERTIES_EX
    };

We chose to show only the relevant part of ``zend_module_entry`` (and ``NULL`` others). Like you can see, globals
management hooks take place in the middle of the structure. The first ``PHP_MODULE_GLOBALS()`` figures out the size of
the globals, then both our ``GINIT`` and ``GSHUTDOWN`` hooks. Then, to close the structure we used
``STANDARD_MODULE_PROPERTIES_EX`` instead of ``STANDARD_MODULE_PROPERTIES``. Just a matter of finishing the structure
the right way, see ?::

    #define STANDARD_MODULE_PROPERTIES \
        NO_MODULE_GLOBALS, NULL, STANDARD_MODULE_PROPERTIES_EX

In the ``GINIT`` function, you are passed a pointer to the current memory location of your globals. You use it to
initialize your globals. Here, we put zero into our random value (not really useful, but let's accept it).

.. warning:: Don't use ``PIB_G()`` macro in GINIT. Use the pointer you are given.

.. note:: ``GINIT()`` is launched before ``MINIT()`` for the current process. In case of NTS, that's all. In case of
            ZTS, ``GINIT()`` will be called additionally for every new thread spawned by the thread library.

.. warning:: ``GINIT()`` is not called as part of ``RINIT()``. If you need to clear your globals at every new request,
             you need to do that by hand, like we did in the example shown throughout the chapter.

Full example
------------

Here is a more advanced full example. If the player wins, its score (numbers of tries) is added to a score array that
can be fetched from userland. Nothing really hard, the score array is initialized at request startup, then used
anytime the player wins, and cleared at the end of the current request::

    ZEND_BEGIN_MODULE_GLOBALS(pib)
        zend_long rnd;
        zend_ulong cur_score;
        zval scores;
    ZEND_END_MODULE_GLOBALS(pib)

    ZEND_DECLARE_MODULE_GLOBALS(pib)

    static void pib_rnd_init(void)
    {
        /* reset current score as well */
        PIB_G(cur_score) = 0;
        php_random_int(0, 100, &PIB_G(rnd), 0);
    }

    PHP_GINIT_FUNCTION(pib)
    {
        /* ZEND_SECURE_ZERO is a memset(0). Could resolve to bzero() as well */
        ZEND_SECURE_ZERO(pib_globals, sizeof(*pib_globals));
    }

    ZEND_BEGIN_ARG_INFO_EX(arginfo_guess, 0, 0, 1)
        ZEND_ARG_INFO(0, num)
    ZEND_END_ARG_INFO()

    PHP_RINIT_FUNCTION(pib)
    {
        array_init(&PIB_G(scores));
        pib_rnd_init();

        return SUCCESS;
    }

    PHP_RSHUTDOWN_FUNCTION(pib)
    {
        zval_dtor(&PIB_G(scores));

        return SUCCESS;
    }

    PHP_FUNCTION(pib_guess)
    {
        zend_long r;

        if (zend_parse_parameters(ZEND_NUM_ARGS(), "l", &r) == FAILURE) {
            return;
        }

        if (r == PIB_G(rnd)) {
            add_next_index_long(&PIB_G(scores), PIB_G(cur_score));
            pib_rnd_init();
            RETURN_TRUE;
        }

        PIB_G(cur_score)++;

        if (r < PIB_G(rnd)) {
            RETURN_STRING("more");
        }

        RETURN_STRING("less");
    }

    PHP_FUNCTION(pib_get_scores)
    {
        if (zend_parse_parameters_none() == FAILURE) {
            return;
        }

        RETVAL_ZVAL(&PIB_G(scores), 1, 0);
    }

    PHP_FUNCTION(pib_reset)
    {
        if (zend_parse_parameters_none() == FAILURE) {
            return;
        }

        pib_rnd_init();
    }

    static const zend_function_entry func[] = {
        PHP_FE(pib_reset, NULL)
        PHP_FE(pib_get_scores, NULL)
        PHP_FE(pib_guess, arginfo_guess)
        PHP_FE_END
    };

    zend_module_entry pib_module_entry = {
        STANDARD_MODULE_HEADER,
        "pib",
        func, /* Function entries */
        NULL, /* Module init */
        NULL, /* Module shutdown */
        PHP_RINIT(pib), /* Request init */
        PHP_RSHUTDOWN(pib), /* Request shutdown */
        NULL, /* Module information */
        "0.1", /* Replace with version number for your extension */
        PHP_MODULE_GLOBALS(pib),
        PHP_GINIT(pib),
        NULL,
        NULL,
        STANDARD_MODULE_PROPERTIES_EX
    };

What must be noted here, is that PHP provides no facility if you would have wanted to persist the scores across
requests. That would have needed a persistent shared storage, such as a file, a database, some memory area, etc...
PHP has not been designed to persist information across requests in its heart, so it provides nothing to do so, but
provides utilities to access request-bound global space like we showed.

Then, easy enough we initialize an array in ``RINIT()``, and we destroy it in ``RSHUTDOWN()``. Remember that
``array_init()`` creates a :doc:`zend_array <../internal_types/hashtables>` and puts it into a
:doc:`zval <../internal_types/zvals>`. But this is allocation-free, do not fear to allocate an array the user could not
make use of (thus a waste in allocation), ``array_init()`` is very cheap (`read the source
<https://github.com/php/php-src/blob/d0b7eed0c9d873a0606dbbc7e33f14492f1a3dd6/Zend/zend_API.c#L1057>`_).

When we return such an array to the user, we don't forget to increment its refcount (in ``RETVAL_ZVAL``) as we keep a
reference to such an array into our extension.

Using true globals
******************

True globals are non-thread-protected-true-C-globals. It may happen sometimes that you need some of them. Remember
however the main rule : you cannot safely write to such globals as you are treating a request. So usually with PHP, we
need such variables and use them as read-only variable.

Remember it is perfectly safe to write to true-globals as you are in the ``MINIT()`` or ``MSHUTDOWN()`` steps of PHP
lifecycle. But you can't write to them while treating a request (but reading from them is OK).

So, a simple example is that you want to read an environment value to do something with it. Also, it is not uncommon to
initialize persistent :doc:`zend_string <../internal_types/strings/zend_strings>` to make use of them later as you'll
treat some requests.

Here is the patched example introducing true globals, we just show the diff about preceding code and not the full code::

    static zend_string *more, *less;
    static zend_ulong max = 100;

    static void register_persistent_string(char *str, zend_string **result)
    {
        *result = zend_string_init(str, strlen(str), 1);
        zend_string_hash_val(*result);

        GC_FLAGS(*result) |= IS_INTERNED;
    }

    static void pib_rnd_init(void)
    {
        /* reset current score as well */
        PIB_G(cur_score) = 0;
        php_random_int(0, max, &PIB_G(rnd), 0);
    }

    PHP_MINIT_FUNCTION(pib)
    {
        char *pib_max;

        register_persistent_string("more", &more);
        register_persistent_string("less", &less);

        if (pib_max = getenv("PIB_RAND_MAX")) {
            if (!strchr(pib_max, '-')) {
                max = ZEND_STRTOUL(pib_max, NULL, 10);
            }
        }

        return SUCCESS;
    }

    PHP_MSHUTDOWN_FUNCTION(pib)
    {
        zend_string_release(more);
        zend_string_release(less);

        return SUCCESS;
    }

    PHP_FUNCTION(pib_guess)
    {
        zend_long r;

        if (zend_parse_parameters(ZEND_NUM_ARGS(), "l", &r) == FAILURE) {
            return;
        }

        if (r == PIB_G(rnd)) {
            add_next_index_long(&PIB_G(scores), PIB_G(cur_score));
            pib_rnd_init();
            RETURN_TRUE;
        }

        PIB_G(cur_score)++;

        if (r < PIB_G(rnd)) {
            RETURN_STR(more);
        }

        RETURN_STR(less);
    }

What happened here is that we created two :doc:`zend_string <../internal_types/strings/zend_strings>` variables ``more``
and ``less``. Those strings don't need to be created and destroyed anytime they are used like it was done before. Those
are immutable strings that can be allocated once and reused anytime needed, as soon as they stay immutable
(aka : read-only). We initialize those two strings in ``MINIT()`` using a persistent allocation in
``zend_string_init()``, we precompute their hash now (instead of having the very first request doing it), and we tell
the zval garbage collector those strings are interned so that it will never ever try to destroy them (however it could
need to copy them if they were used as part of a write operation, such as a concatenation). Obviously we don't forget
to destroy such strings in ``MSHUTDOWN()``.

Then in ``MINIT()`` we probe for a ``PIB_RAND_MAX`` environment and use it as the maximum range value for our random
number pick. As we use an unsigned integer and we know ``strtoull()`` won't complain about negative numbers (and thus
wrap around integer bounds as sign mismatch), we just avoid using negative (classic libc workarounds).
