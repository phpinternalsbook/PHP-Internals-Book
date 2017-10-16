Registering and using PHP functions
===================================

The main goal of a PHP extension is to register new PHP functions for userland. PHP functions are complex to fully
understand their mechanics that hook very deep into the Zend Engine, but fortunately we don't need this knowledge
for our chapter, as the PHP extension mechanism provides many ways to abstract a lot such a complexity.

Registering and using new PHP functions in an extension is an easy step. Deeply understanding the big picture is
however pretty more complex. A first step :doc:`to the zend_function chapter<../internal_types/functions>` could help
then.

Obviously, you'll need to master :doc:`types<../internal_types>`, especially :doc:`zvals<../internal_types/zvals>` and
:doc:`memory management<../memory_management>` here. Also, know your :doc:`hooks<../extensions_design/php_lifecycle>`.

zend_function_entry structure
*****************************

Not to be confused with :doc:`the zend_function structure<../internal_types/functions>`, ``zend_function_entry`` is
used to register functions against the engine while in an extension.
Here it is::

    #define INTERNAL_FUNCTION_PARAMETERS zend_execute_data *execute_data, zval *return_value

    typedef struct _zend_function_entry {
	    const char *fname;
	    void (*handler)(INTERNAL_FUNCTION_PARAMETERS);
	    const struct _zend_internal_arg_info *arg_info;
	    uint32_t num_args;
	    uint32_t flags;
    } zend_function_entry;

You can spot that this structure is not complex. This is all you'll need to declare and register a new function.
Let's detail it together:

A function's got a name: ``fname``. Nothing to add, you see what it's used for right? Just notice the ``const char *`` 
type. That can't fit into the engine. This ``fname`` is a model and the engine will create from it an 
:doc:`interned zend_string<../internal_types/strings/zend_strings>`.

Then comes the ``handler``. This is a function pointer to the C code that will be the body of that function. Here, 
we'll use macros to ease its declaration (we'll see that in a minute). Into this function, we'll be able to parse the 
parameters the function receives, and generate a return value just like any PHP userland function. Notice that this 
return value is passed to our handler as a parameter.

Arguments. The ``arg_info`` variable is about declaring the API arguments our function will accept. Here again, 
that part can be tricky to deeply understand, but we don't need to get too deep and we'll once more use macros to 
abstract and ease arguments declaration. What you should know is that you are not required to declare any arguments 
here for the function to work, but it is highly recommanded. We'll get back to that. Arguments are an array of
``arg_info``, and thus its size is passed as ``num_args``.

Then come ``flags``. We won't detail flags in this chapter. Those are used internally, you'll find some details in the 
dedicated :doc:`zend_function<../internal_types/functions>` chapter.

Registering PHP functions
*************************

PHP functions are registered into the engine when the extension gets loaded. An extension may declare a function vector
into the extension structure. Functions declared by extensions are called "internal" functions, and at the opposite of
"user" functions (functions declared and used using PHP userland) they don't get unregistered at the end of the
current request: they are permanent.

As a reminder, here is the PHP extension structure shorten for readability::

    struct _zend_module_entry {
	    unsigned short size;
	    unsigned int zend_api;
	    unsigned char zend_debug;
	    unsigned char zts;
	    const struct _zend_ini_entry *ini_entry;
	    const struct _zend_module_dep *deps;
	    const char *name;
	    const struct _zend_function_entry *functions;     /* function declaration vector */
	    int (*module_startup_func)(INIT_FUNC_ARGS);
	    int (*module_shutdown_func)(SHUTDOWN_FUNC_ARGS);
        /* ... */
    };

You'll pass to the function vector a declared vector of functions. Let's see together a simple example::

    /* pib.c */
    PHP_FUNCTION(fahrenheit_to_celsius)
    {

    }
    
    static const zend_function_entry pib_functions[] =
    {
        PHP_FE(fahrenheit_to_celsius, NULL)
    };

    zend_module_entry pib_module_entry = {
        STANDARD_MODULE_HEADER,
        "pib",
        pib_functions,
        NULL,
        NULL,
        NULL,
        NULL,
        NULL,
        "0.1",
        STANDARD_MODULE_PROPERTIES
    };

Let's play with a simple ``fahrenheit_to_celsius()`` function (which name tells us what it will perform).

Defining a function is done by using the ``PHP_FUNCTION()`` macro. That latter will take its argument and expand to the 
right structure.
Then, we gather that function symbol and add it to the ``pib_functions`` vector. This is on type 
``zend_function_entry *``, the type extected by our ``zend_module_entry`` symbol. Into this vector, we add our PHP 
functions using the ``PHP_FE`` macro. That latter needs the PHP function name, and an argument vector which we passed 
NULL for the moment.

You can register your function under a specific namespace using the `ZEND_NS_NAMED_FE` macro, this macro
takes four parameters :

    * the namespace string, e.g: "Pib\\Book".
    * the function name, this will be the final function name under the new namespace, for example lets call it : `f2c`.
    * the function handler, from our example: `fahrenheit_to_celsius`.
    * the arg info which will be covered in this chapter.

So the final `zend_function_entry` would be something like::

    static const zend_function_entry pib_functions[] =
    {
        ZEND_NS_NAMED_FE("Pib\\Book", f2c, fahrenheit_to_celsius, NULL)
    };

Note that your new function will take a new name here which will be `f2c`.

Into our *php_pib.h* header file, we should here declare our function, like the C language tells us to do so::

    /* pib.h */
    PHP_FUNCTION(fahrenheit_to_celsius);

Like you can see, it is really easy to declare functions. The macros do all the hard job for us.
Here is the same code, but with the macros expanded, so that you can have a look at their job::

    /* pib.c */
    void zif_fahrenheit_to_celsius(zend_execute_data *execute_data, zval *return_value)
    {

    }
    
    static const zend_function_entry pib_functions[] =
    {
        { "fahrenheit_to_celsius", zif_fahrenheit_to_celsius, ((void *)0), 
            (uint32_t) (sizeof(((void *)0))/sizeof(struct _zend_internal_arg_info)-1), 0 },
    }

Notice how ``PHP_FUNCTION()`` expanded to a C symbol beginning by ``zif_``. *'zif'* stands for
*Zend Internal Function*, it is added to the name of your function to prevent symbol name collisions in the compilation
of PHP and its modules. Thus, our ``fahrenheit_to_celsius()`` PHP function uses a C handler named
``zif_fahrenheit_to_celsius()``. It is the same for nearly every PHP function. If you look for "zif_var_dump", you'll
read the PHP ``var_dump()`` source code function, etc...

Declaring function arguments
****************************

So far so good, if :doc:`you compile<../build_system/building_extensions>` the extension and load it into PHP, you can
see with reflection that the function is present::

    > ~/php/bin/php -dextension=pib.so --re pib
    Extension [ <persistent> extension #37 pib version 0.1 ] {

      - Functions {
        Function [ <internal:pib> function fahrenheit_to_celsius ] {
        }
    }

But its arguments are missing. If we want to publish a ``fahrenheit_to_celsius($fahrenheit)`` function signature, we
need one mandatory argument.

What you must know is that argument declaration has nothing to do with the function internal work. That means that this
function could have worked if we would have written its body now. Even with no declared arguments.

.. note:: Declaring arguments is not mandatory but highly recommanded. Arguments are used by the reflection API to get 
          informations about the function. Arguments are also used by the engine, especially when we talk about 
          arguments passed by reference, or functions returning references.

To declare arguments, we need to familiarize with the ``zend_internal_arg_info`` structure::

    typedef struct _zend_internal_arg_info {
	    const char *name;
	    const char *class_name;
	    zend_uchar type_hint;
	    zend_uchar pass_by_reference;
	    zend_bool allow_null;
	    zend_bool is_variadic;
    } zend_internal_arg_info;

No need to detail every field, but the understanding of the arguments is more complex than this solo structure.
Fortunately, you are once more provided some macros to abstract the hard job for you::

    ZEND_BEGIN_ARG_INFO_EX(arginfo_fahrenheit_to_celsius, 0, 0, 1)
        ZEND_ARG_INFO(0, fahrenheit)
    ZEND_END_ARG_INFO()

The code above details how to create an argument, but when we expand macros, we can feel some difficulty::

    static const zend_internal_arg_info arginfo_fahrenheit_to_celsius[] = { \
		{ (const char*)(zend_uintptr_t)(1), ((void *)0), 0, 0, 0, 0 },
		{ "fahrenheit", ((void *)0), 0, 0, 0, 0 },
	};

As we can see, a ``zend_internal_arg_info`` structure is created by the macros.
If you read the API of such macros, then all becomes clear to us::

    /* API only */
    #define ZEND_BEGIN_ARG_INFO_EX(name, _unused, return_reference, required_num_args)
    #define ZEND_ARG_INFO(pass_by_ref, name)
    #define ZEND_ARG_OBJ_INFO(pass_by_ref, name, classname, allow_null)
    #define ZEND_ARG_ARRAY_INFO(pass_by_ref, name, allow_null)
    #define ZEND_ARG_CALLABLE_INFO(pass_by_ref, name, allow_null)
    #define ZEND_ARG_TYPE_INFO(pass_by_ref, name, type_hint, allow_null)
    #define ZEND_ARG_VARIADIC_INFO(pass_by_ref, name)

This bunch of macros allow you to deal with every use-case.

* The ``ZEND_BEGIN_ARG_INFO_EX()`` allows you to declare how many required arguments your function accept. It also 
  allows to declare a *&return_by_ref()* function.
* Then you need one of the ``ZEND_ARG_***_INFO()`` per argument. Using it you can tell if the argument is 
  *&$passed_by_ref* and if you need a type hint.

.. note:: If you don't know how to name the arguments vector symbol, a practice is to use the 
          *'arginfo_[function name]'* pattern.

So back to our ``fahrenheit_to_celsius()`` function, we declare a simple return by value function (very classical 
use-case), with one argument called ``fahrenheit``, not passed by reference (here again, very traditional).

That created the ``arginfo_fahrenheit_to_celsius`` symbol of type ``zend_internal_arg_info[]`` (a vector, or an array, 
that is the same), and we must now use that back into our function declaration to attach it some args::

    PHP_FE(fahrenheit_to_celsius, arginfo_fahrenheit_to_celsius)

And we are done, now the reflection sees the argument and the engine is told about what to do in case of reference 
mismatch. Great!

.. note:: There exists other macros. ``ZEND_BEGIN_ARG_WITH_RETURN_TYPE_INFO_EX()`` f.e. You may find all of them into 
          the source code located in 
          `Zend/zend_api.h <https://github.com/php/php-src/blob/648be8600ff89e1b0e4a4ad25cebad42b53bed6d/Zend/
          zend_API.h>`_

The PHP function structure and API, in C
****************************************

Ok. Here is a PHP function like you use it and declare it with the PHP language (userland):

.. code-block:: php

    function fahrenheit_to_celsius($fahrenheit)
    {
        return 5/9 * ($fahrenheit - 32);
    }

This is an easy function so that you understand things.
Here is what it looks like when programmed in C::

    PHP_FUNCTION(fahrenheit_to_celsius)
    {
        /* code to go here */
    }

Macro expanded, that gives::

    void zif_fahrenheit_to_celsius(zend_execute_data *execute_data, zval *return_value)
    {
        /* code to go here */
    }

Take a break and think about the major differences.

First strange thing, in C, the function is not expected to return anything. That's a ``void`` declared function, you 
can't here in C return something. But we notice we receive an argument called ``return_value`` of type ``zval *``, 
which seems to smell very nice. In programming PHP function in C, you are given the return value as a pointer to a 
zval, and you are expected to play with it. :doc:`Here are more resources about zvals<../internal_types/zvals>`.

.. note:: While programming PHP functions in C extensions, you receive the return value as an argument, and you don't 
          return anything from your C function body.

Ok first point explained. Second one as you may have guessed: where are the PHP function arguments? Where is 
``$fahreinheit``? That one is pretty hard to fully explain, it is hell hard to in fact.

But we don't need to have a look at the details here. Let's explain the crucial concepts:

* The arguments have been pushed by the engine onto a stack. They are all stacked next to each other somewhere in 
  memory.
* If your function is called, that means no blocking error thus you'll be able to browse the argument stack and read 
  the runtime passed arguments. Not only those you declared, but those that have been passed to your function when it's 
  been called. The engine takes care of everything for you.
* To read arguments, you need a function or a macro, and you need to be told how many arguments have been pushed onto 
  the stack, to know until when you should end reading them.
* Everything goes by the ``zend_execute_data *execute_data`` you received as argument. But we can't detail that now.

Parsing parameters : zend_parse_parameters()
--------------------------------------------

To read arguments, welcome ``zend_parse_parameters()`` API (called 'zpp').

.. note:: While programming PHP functions in C extensions, you receive PHP function arguments thanks to the 
          ``zend_parse_parameters()`` function and its friends.

``zend_parse_parameters()`` is the function that will read arguments onto the Zend engine stack for you. You will tell 
it how many arguments to read, and on what kind of type you want it to serve you. That function will convert the 
argument to the type you ask, if that is needed, and possible, according to PHP type cast rules. If you need an 
integer, and are given a float, and if no strict type hint rule would have blocked, then the engine will convert the 
float as an integer, and give it to you.

Let's see that function::

    PHP_FUNCTION(fahrenheit_to_celsius)
    {
        double f;

        if (zend_parse_parameters(ZEND_NUM_ARGS(), "d", &f) == FAILURE) {
            return;
        }

        /* continue */
    }

We want to be given a double on the f variable. We then call ``zend_parse_parameters()``.

The first argument is the number of arguments the runtime have been given. ``ZEND_NUM_ARGS()`` is a macro that tells 
us, we then use it to tell zpp() how many arguments to read.

Then, we pass a ``const char *`` , the *"d"* string. Here, you are expected to write one letter per argument to receive, 
except some special cases not taught here. A simple *"d"* means *"I want the first received argument to be 
converted-if-needed to a float (double)"*.

Then, you pass after that string as many C real arguments as needed to satisfy the second argument. One *"d"* means "one 
double", then you pass now **the address of** a double, and the engine will fill its value.

.. note:: You always pass a pointer to the data you want to be populated.

You will find an up-to-date help on zpp()'s string format in the 
`README.PARAMETER_PARSING_API <https://github.com/php/php-src/blob/ef4b2fc283ddaf9bd692015f1db6dad52171c3ce/
README.PARAMETER_PARSING_API>`_ file in the PHP source code. Read it carefully, because here is a step where you 
could mess things up and generate crashes. Always check your parameters, always pass the same number of argument 
variable as you are expecting according to the format string you provided, and of the same type you asked for.
Be logical.

Please, note also the normal procedure of argument parsing. The function ``zend_parse_parameters()`` should return 
``SUCCESS`` on success or ``FAILURE`` on failure. Failure could mean you did not use the ``ZEND_NUM_ARGS()`` value but 
provided a value by hand (bad idea), or you did something wrong in argument parsing. If it is the case, it's then time 
to return, abort the current function (you should return ``void`` from your C function, so just ``return``).

So far so good, we received a double. Let's now perform the math operations and return a result::

    static double php_fahrenheit_to_celsius(double f)
    {
        return ((double)5/9) * (double)(f - 32);
    }

    PHP_FUNCTION(fahrenheit_to_celsius)
    {
        double f;

        if (zend_parse_parameters(ZEND_NUM_ARGS() TSRMLS_CC, "d", &f) == FAILURE) {
            return;
        }

        RETURN_DOUBLE(php_fahrenheit_to_celsius(f));
    }

Returning values should be easy to you, as you know :doc:`how zvals work <../internal_types/zvals>`. You must fill-in 
the ``return_value``.

To do that, some ``RETURN_***()`` macros are dedicated as well as some ``RETVAL_***()`` ones.
Both just set the type and value of the ``return_value`` zval, but ``RETURN_***()`` ones will follow that by a C 
``return`` that will return from that current function.

Alternatively, the API provides a set of macros to handle and parse parameters. It's more readable if you get 
messed with the python style specifiers.

You will need to start and end function parameters parsing with the following macros::

    ZEND_PARSE_PARAMETERS_START(min_argument_count, max_argument_count) /* takes two parameters */
    /* here we will go with argument lists */
    ZEND_PARSE_PARAMETERS_END();

The available parameters macros could be listed as follows::

    Z_PARAM_ARRAY()                /* old "a" */
    Z_PARAM_ARRAY_OR_OBJECT()      /* old "A" */
    Z_PARAM_BOOL()                 /* old "b" */
    Z_PARAM_CLASS()                /* old "C" */
    Z_PARAM_DOUBLE()               /* old "d" */
    Z_PARAM_FUNC()                 /* old "f" */
    Z_PARAM_ARRAY_HT()             /* old "h" */
    Z_PARAM_ARRAY_OR_OBJECT_HT()   /* old "H" */
    Z_PARAM_LONG()                 /* old "l" */
    Z_PARAM_STRICT_LONG()          /* old "L" */
    Z_PARAM_OBJECT()               /* old "o" */
    Z_PARAM_OBJECT_OF_CLASS()      /* old "O" */
    Z_PARAM_PATH()                 /* old "p" */
    Z_PARAM_PATH_STR()             /* old "P" */
    Z_PARAM_RESOURCE()             /* old "r" */
    Z_PARAM_STRING()               /* old "s" */
    Z_PARAM_STR()                  /* old "S" */
    Z_PARAM_ZVAL()                 /* old "z" */
    Z_PARAM_VARIADIC()             /* old "+" and "*" */

And to add a parameter as an optional parameter we use the following macro::

     Z_PARAM_OPTIONAL              /* old "|" */

Here is our example with the macro-based parameters parsing style::

    PHP_FUNCTION(fahrenheit_to_celsius)
    {
        double f;

        ZEND_PARSE_PARAMETERS_START(1, 1)
            Z_PARAM_DOUBLE(f);
        ZEND_PARSE_PARAMETERS_END();

        RETURN_DOUBLE(php_fahrenheit_to_celsius(f));
    }

Adding tests
************

If you have read the chapter about tests (see :ref:`tests_introduction`), you should now write a simple test::

    --TEST--
    Test fahrenheit_to_celsius
    --SKIPIF--
    <?php if (!extension_loaded("pib")) print "skip"; ?>
    --FILE--
    <?php 
    printf("%.2f", fahrenheit_to_celsius(70));
    ?>
    --EXPECTF--
    21.11

\... and launch ``make test``

Playing with constants
**********************

Let's go with an advanced example.
Let's add the opposite function: ``celsius_to_fahrenheit($celsius)``::

    ZEND_BEGIN_ARG_INFO_EX(arginfo_celsius_to_fahrenheit, 0, 0, 1)
        ZEND_ARG_INFO(0, celsius)
    ZEND_END_ARG_INFO();

    static double php_celsius_to_fahrenheit(double c)
    {
        return (((double)9/5) * c) + 32 ;
    }

    PHP_FUNCTION(celsius_to_fahrenheit)
    {
        double c;

        if (zend_parse_parameters(ZEND_NUM_ARGS(), "d", &c) == FAILURE) {
            return;
        }

        RETURN_DOUBLE(php_celsius_to_fahrenheit(c));
    }

    static const zend_function_entry pib_functions[] =
    {
        PHP_FE(fahrenheit_to_celsius, arginfo_fahrenheit_to_celsius) /* Done above */
        PHP_FE(celsius_to_fahrenheit,arginfo_celsius_to_fahrenheit) /* just added */
        PHP_FE_END
    };
    
Now a more complex use case, we show it in PHP before implementing it as a C extension:

.. code-block:: php

    const TEMP_CONVERTER_TO_CELSIUS     = 1;
    const TEMP_CONVERTER_TO_FAHREINHEIT = 2;

    function temperature_converter($temp, $type = TEMP_CONVERTER_TO_CELSIUS)
    {
        switch ($type) {
            case TEMP_CONVERTER_TO_CELSIUS:
                return sprintf("%.2f degrees fahrenheit gives %.2f degrees celsius", $temp, 
                                fahrenheit_to_celsius($temp));
            case TEMP_CONVERTER_TO_FAHREINHEIT:
                return sprintf("%.2f degrees celsius gives %.2f degrees fahrenheit, $temp, 
                                celsius_to_fahrenheit($temp));
            default:
                trigger_error("Invalid mode provided, accepted values are 1 or 2", E_USER_WARNING);
            break;
        }
    }

That example helps us introduce **constants**.

Constants are easy to manage in extensions, like they are in their userland counter-part. Constants are persistent, 
most often, that means that they should persist their value across requests. If you are aware of
:doc:`the PHP lifecycle<./php_lifecycle>`, you should have guessed that ``MINIT()`` is the right stage to register 
constants against the engine.

Here is a constant, internally, a ``zend_constant`` structure::

    typedef struct _zend_constant {
        zval value;
        zend_string *name;
        int flags;
        int module_number;
    } zend_constant;

Really an easy structure (that could become a nightmare if you deeply look at how constants are managed into the 
engine). You declare a ``name``, a ``value``, some ``flags`` (not many) and the ``module_number`` is automatically set 
to your extension number (no need to take care of that).

To register constants, here again there is no difficulty at all, a bunch of macros do the job for you::

    #define TEMP_CONVERTER_TO_FAHRENHEIT 2
    #define TEMP_CONVERTER_TO_CELSIUS 1

    PHP_MINIT_FUNCTION(pib)
    {
        REGISTER_LONG_CONSTANT("TEMP_CONVERTER_TO_CELSIUS", TEMP_CONVERTER_TO_CELSIUS, CONST_CS|CONST_PERSISTENT);
        REGISTER_LONG_CONSTANT("TEMP_CONVERTER_TO_FAHRENHEIT", TEMP_CONVERTER_TO_FAHRENHEIT, CONST_CS|CONST_PERSISTENT);

        return SUCCESS;
    }

.. note:: It is a good practice to give PHP constants values of C macros. That ease things, and that's what we did.

Depending on your constant type, you'll use ``REGISTER_LONG_CONSTANT()``, ``REGISTER_DOUBLE_CONSTANT()``, etc...
API and macros are located into 
`Zend/zend_constants.h <https://github.com/php/php-src/blob/648be8600ff89e1b0e4a4ad25cebad42b53bed6d/Zend/
zend_constants.h>`_.

The flags are mixed *OR* operation between ``CONST_CS`` (case-sensitive constant, what we want), and 
``CONST_PERSISTENT`` (a persistent constant, across requests, what we want as well).

Now our ``temperature_converter($temp, $type = TEMP_CONVERTER_TO_CELSIUS)`` function in C::

    ZEND_BEGIN_ARG_INFO_EX(arginfo_temperature_converter, 0, 0, 1)
        ZEND_ARG_INFO(0, temperature)
        ZEND_ARG_INFO(0, mode)
    ZEND_END_ARG_INFO();

We got one mandatory argument, out of two. That's what we declared. Its default value is not a deal argument 
declaration can solve, that will be done in a second.

Then we add our new function to the function registration vector::

    static const zend_function_entry pib_functions[] =
    {
        PHP_FE(fahrenheit_to_celsius,arginfo_fahrenheit_to_celsius) /* seen above */
        PHP_FE(celsius_to_fahrenheit,arginfo_celsius_to_fahrenheit) /* seen above */
        PHP_FE(temperature_converter, arginfo_temperature_converter) /* our new function */
    }

And, the function body::

    PHP_FUNCTION(temperature_converter)
    {
        double t;
        zend_long mode = TEMP_CONVERTER_TO_CELSIUS;
        zend_string *result;

        if (zend_parse_parameters(ZEND_NUM_ARGS(), "d|l", &t, &mode) == FAILURE) {
            return;
        }

        switch (mode)
        {
            case TEMP_CONVERTER_TO_CELSIUS:
                result = strpprintf(0, "%.2f degrees fahrenheit gives %.2f degrees celsius", t, php_fahrenheit_to_celsius(t));
                RETURN_STR(result);
            case TEMP_CONVERTER_TO_FAHRENHEIT:
                result = strpprintf(0, "%.2f degrees celsius gives %.2f degrees fahrenheit", t, php_celsius_to_fahrenheit(t));
                RETURN_STR(result);
            default:
                php_error(E_WARNING, "Invalid mode provided, accepted values are 1 or 2");
        }
    }

Remember to well look at `README.PARAMETER_PARSING_API <https://github.com/php/php-src/blob/
ef4b2fc283ddaf9bd692015f1db6dad52171c3ce/README.PARAMETER_PARSING_API>`_. It's not a hard API, you must familiarize 
with it.

We use *"d|l"* as arguments to ``zend_parse_parameters()``. One double and optionaly (the pipe *"|"*) one long. Take 
care, if the optional argument is not provided at runtime (what ``ZEND_NUM_ARGS()`` tells us about, as a reminder), 
then the ``&mode`` variable won't be touched by zpp(). That's why we provide a default value of
``TEMP_CONVERTER_TO_CELSIUS`` to that variable.

Then we use ``strpprintf()`` to build a :doc:`zend_string <../internal_types/strings/zend_strings>`, and return it into 
the ``return_value`` zval using ``RETURN_STR()``.

.. note:: ``strpprintf()`` and its sisters are explained in 
          :doc:`the chapter about printing functions <../internal_types/strings/printing_functions>`.

A go with Hashtables (PHP arrays)
*********************************

Let's go now for a play with *PHP arrays* and design:

.. code-block:: php

    function multiple_fahrenheit_to_celsius(array $temperatures)
    {
        foreach ($temperatures as $temp) {
            $return[] = fahreinheit_to_celsius($temp);
        }

        return $return;
    }
    
So thinking at the C implementation, we need to ``zend_parse_parameters()`` and ask for just one array, iterate over it, 
make the maths operations and add the result in ``return_value``, as an array::

    ZEND_BEGIN_ARG_INFO_EX(arginfo_multiple_fahrenheit_to_celsius, 0, 0, 1)
        ZEND_ARG_ARRAY_INFO(0, temperatures, 0)
    ZEND_END_ARG_INFO();

    static const zend_function_entry pib_functions[] =
    {
	    /* ... */
        PHP_FE(multiple_fahrenheit_to_celsius, arginfo_multiple_fahrenheit_to_celsius)
        PHP_FE_END
    };

    PHP_FUNCTION(multiple_fahrenheit_to_celsius)
    {
        HashTable *temperatures;
        zval *data;

        if (zend_parse_parameters(ZEND_NUM_ARGS(), "h", &temperatures) == FAILURE) {
            return;
        }
        if (zend_hash_num_elements(temperatures) == 0) {
    	    return;
        }

        array_init_size(return_value, zend_hash_num_elements(temperatures));

        ZEND_HASH_FOREACH_VAL(temperatures, data)
            zval dup;
            ZVAL_COPY_VALUE(&dup, data);
            convert_to_double(&dup);
        add_next_index_double(return_value, php_fahrenheit_to_celsius(Z_DVAL(dup)));
        ZEND_HASH_FOREACH_END();
    }


.. note:: You need to know :doc:`how Hashtables work<../internal_types/hashtables>`, and the must-read 
          :doc:`zval chapter<../internal_types/zvals>`

Here, the C part will be faster, as you don't call a PHP function in the loop for the C code, but a static (and probably 
inlined by the compiler) C function, which is orders of magnitude faster and requires tons less of low-level CPU 
instructions to run. It's not about that little demo function needs so much love in code performance, it's just to 
remember one reason why we sometimes use the C language over PHP.

Managing references
*******************

Now let's go to play with PHP references. You've learnt from :doc:`the zval chapter <../internal_types/zvals>` that
references are a special trick used into the engine. As a reminder, a reference (by that we mean a ``&$php_reference``)
is a heap allocated ``zval`` stored into a ``zval`` container. Haha.

So, it is not very hard to deal with those into PHP functions, as soon as you remember what references are, and what
they're designed to.

If your function accept a parameter as a reference, you must declare that in arguments signature and be passed a
reference from your ``zend_parse_parameter()`` call. Let's see that like always, with a PHP example first:

.. code-block::php

    function fahrenheit_to_celsius_by_ref(&$fahreinheit)
    {
        $fahreinheit = 9/5 * $fahrenheit + 32;
    }

So now in C, first we must change our ``arg_info``::

    ZEND_BEGIN_ARG_INFO_EX(arginfo_fahrenheit_to_celsius, 0, 0, 1)
        ZEND_ARG_INFO(1, fahrenheit)
    ZEND_END_ARG_INFO();
    
*1*, passed in the ``ZEND_ARG_INFO()`` macro tells the engine that argument must be passed by reference.

Then, when we receive the argument, we use the *"z"* argument type, to tell that we want to be given it as a ``zval *``.
As we did hint the engine about the fact that it should pass us a reference, we'll be given a reference into that zval,
aka it will be of type ``IS_REFERENCE``. We just need to dereference it (that is to fetch the zval stored into the
zval), and modify it as-is, as the expected behavior of references is that you must modify the value carried by the
reference::

    PHP_FUNCTION(fahrenheit_to_celsius)
    {
        double result;
        zval *param;

        if (zend_parse_parameters(ZEND_NUM_ARGS(), "z", &param) == FAILURE) {
            return;
        }

        ZVAL_DEREF(param);
        convert_to_double(param);

        ZVAL_DOUBLE(param, php_fahrenheit_to_celsius(Z_DVAL_P(param)));
    }

Done.

.. note:: The default ``return_value`` value is ``NULL``. If we don't touch it, the function will return PHP's ``NULL``.
