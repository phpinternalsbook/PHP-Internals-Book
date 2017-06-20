Zend Extensions
===============

PHP knows two kinds of extensions : 

* The PHP extensions, the most commonly used
* The Zend extensions, more uncommon, allows other hooks

This chapter will detail what are the main differences between Zend extensions and PHP extensions, when you should one 
instead of the other, and how to build hybrid extensions, aka extensions being both PHP and Zend at the same time (and 
why do that)

On differences between PHP and Zend extensions
**********************************************

Just to say. Into PHP's source code, PHP extensions are named as **"PHP modules"**, whereas Zend extensions are called 
**"Zend extensions"**.

So into PHP's heart, if you read the "extension" keyword, you should first think about a Zend extension. And if you 
read the "module" keyword, you may think about a PHP extension.

In traditionnal life, we talk about *"PHP extensions"* versus *"Zend extensions"*.

The thing that differentiate them is the way they are loaded :

* PHP extensions (aka PHP "modules") are loaded in INI files as a *"extension=pib.so"* line
* Zend extensions are loaded in INI files as a *"zend_extension=pib.so"* line

That's the only visible difference we see from PHP userland.

But that's a different story from internal point of view.

What is a Zend extension ?
**************************

First of all, Zend extensions are compiled and loaded the same way as PHP extensions. Thus, if you haven't yet read the 
:doc:`building PHP extensions <../build_system/building_extensions>` chapter, you should have a look as it is valid 
also for Zend extensions.

.. note:: If not done, :doc:`get some informations about PHP extensions <../extensions_design>` as we will compare 
          against them here.

Here is a Zend extension. Note that you need to publish not one but two structures for the engine to load your Zend 
extension::

    /* Main Zend extension structure */
    struct _zend_extension {
        char *name;                                           /*
        char *version;                                         * Some infos
        char *author;                                          *
        char *URL;                                             *
        char *copyright;                                       */

        startup_func_t startup;                               /*
        shutdown_func_t shutdown;                              *  Specific branching lifetime points
        activate_func_t activate;                              *  ( Hooks )
        deactivate_func_t deactivate;                          */

        message_handler_func_t message_handler;               /* Hook called on zend_extension registration */

        op_array_handler_func_t op_array_handler;             /* Hook called just after Zend compilation */

        statement_handler_func_t statement_handler;           /*
        fcall_begin_handler_func_t fcall_begin_handler;        *  Hooks called through the Zend VM as specific OPCodes
        fcall_end_handler_func_t fcall_end_handler;            */

        op_array_ctor_func_t op_array_ctor;                   /* Hook called on OPArray construction */
        op_array_dtor_func_t op_array_dtor;                   /* Hook called on OPArray destruction */

        int (*api_no_check)(int api_no);                      /* Checks against zend_extension incompatibilities
        int (*build_id_check)(const char* build_id);           */
        
        op_array_persist_calc_func_t op_array_persist_calc;   /* Hooks called if the zend_extension extended the
        op_array_persist_func_t op_array_persist;              * OPArray structure and has some SHM data to declare
                                                               */

        void *reserved5;                                      /*
        void *reserved6;                                       * Do what you want with those free pointers
        void *reserved7;                                       *
        void *reserved8;                                       */

        DL_HANDLE handle;                                     /* dlopen() returned handle */
        int resource_number;                                  /* internal number used to manage that extension */
    };
    
    /* Structure used when the Zend extension get loaded into the engine */
    typedef struct _zend_extension_version_info {
        int zend_extension_api_no;
        char *build_id;
    } zend_extension_version_info;

.. note:: As always, read the source. Zend extensions are managed into 
          `Zend/zend_extension.c <https://github.com/php/php-src/blob/57dba0e2f5e39f6b05031317048e39d463243cc3/Zend/
          zend_extensions.c>`_ (and .h)

Like you can notice, Zend extensions are more complex than PHP extensions, as they got more hooks, and those are much 
closer to the Zend engine and its Virtual Machine (The most complex parts of the whole PHP source code).

Let us warn you : until you have very advanced knowledge on PHP internal's Vritual Machine, and until you need to hook 
deep into it, you shouldn't need a Zend extension, but a PHP extension will be enough.

Today's most commonly known Zend extensions into PHP's world are OPCache, XDebug, phpdbg and Blackfire. But you know 
dozens of PHP extensions next to that don't you ?! That's a clear sign that :

* You should not need a Zend extension for a very big part of your problematics
* Zend extensions can also be used as PHP extensions (more on that later)
* A PHP extension still can do a lot of things.

.. note:: There is no :doc:`skeleton generator <extension_skeleton>` for Zend extensions, like for PHP extensions.

.. warning:: With Zend extensions, no generator, no help. Zend extensions are reserved to advanced programmers, they 
             are more complex to understand, they got deeper-engine behaviors and usually require an advanced knowledge 
             of PHP's internal machinery.

API versions and conflicts management
*************************************

You know that PHP extensions check against several rules before loading, to know if they are compatible with the PHP 
version you try to load them on. This has been detailed into 
:doc:`the chapter about building PHP extensions <../build_system/building_extensions>`.

For Zend extension, the same rules apply, but a little bit differently : Instead of the engine trashing you away in 
case of mismatch in numbers, it will use the ``zend_extension_version_info`` structure you published to know what to do.

The ``ZEND_EXTENSION_API_NO`` is checked when your Zend extension is loaded. But the difference is that if this number 
doesn't match your Zend extension's, you still have a chance to get loaded. The engine will call for your 
``api_no_check()``hook, if you declared one, and will pass it the ``ZEND_EXTENSION_API_NO``. Here, you must tell if you 
support that API number, or not.

The same applies to the other ABI settings, such as ``ZEND_DEBUG``, or ``ZTS``. Where PHP extensions will refuse to 
load if there is a mismatch, Zend extensions are given a chance to load as the engine checks against 
``build_id_check()`` hook and pass it the ``ZEND_EXTENSION_BUILD_ID``. Here again, you say if you are compatible or not.

Those abilities to force things against the engine are rarely used in practice.

.. note:: You see how more complex Zend extensions are compared to PHP extensions ? The engine is less restrictive, and 
          it suppose that you know what you do, for the best or the worst.
          
.. warning:: Zend extensions should really be developped by experienced and advanced programmers, as the engine is 
             weaker about its checks. It clearly supposes that you master what you do.

To sum things up about API compatibility, well, every step is detailed in 
`zend_load_extension() <https://github.com/php/php-src/blob/57dba0e2f5e39f6b05031317048e39d463243cc3/Zend/
zend_extensions.c#L67>`_.

Then comes the problem of Zend extension conflicts. One may be incompatible with an other, and to master that, every 
Zend extension has got a hook called ``message_handler``. If declared, this hook is triggered on every already loaded 
extension when another Zend extension gets loaded. You are passed a pointer to its ``zend_extension`` structure, and you 
may then detect which one it is, and abort if you think you'll confict with it. This is something rarely used.

Zend extensions lifetime hooks
******************************

If you remember about :doc:`the PHP lifecycle <php_lifecycle>` (you should read the dedicated chapter), well, Zend 
extensions plug into that lifecycle this way:

.. image:: ./images/php_extensions_lifecycle_full.png
   :align: center
   
We can notice that our ``api_no_check()``, ``build_id_check()`` and ``message_handler()`` check hooks are only triggered 
when PHP starts up. Those later three hooks are detailed in the preceding part (above).

Then the **important** thing to remember :

* ``MINIT()`` is triggered on PHP extensions **before** Zend extensions (``startup()``).
* ``RINIT()`` is triggered of Zend extensions (``activate()``) **before** PHP extensions.
* Zend extensions request shutdown procedure (``deactivate()``) is called **in between** ``RSHUTDOWN()`` and 
  ``PRSHUTDOWN()`` for PHP extensions.
* ``MSHUTDOWN()`` is called on PHP extensions **first**, then on Zend extensions **after** (``shutdown()``).

.. warning:: Like for every hook, there is a precise defined order and you must master it and remember it for complex 
             use-case extensions.

In *practice*, what we can say about it is that :

* Zend extensions are started **after** PHP extensions. That allows Zend extensions to be sure that every PHP extension 
  is already loaded when they start. They are then able to replace-and-hook into PHP extensions. For example, if you need 
  to replace the ``session_start()`` function handler by yours, it will be easier to do so in a Zend extension. If you do 
  it in a PHP extension, you must be sure you get loaded after the session extension, and that can be tricky to check and 
  to master (You still can specify a dependency using a `zend_module_dep <https://github.com/php/php-src/blob/
  c18ba686cdf2d937475eb3d5c239e4ef8e733fa6/Zend/zend_modules.h#L118>`_).
  However, :doc:`remember <extension_skeleton>` that statically compiled extensions are always started before 
  dynamically compiled ones. Thus, for the session use-case, this is not a problem as *ext/session* is loaded as static.
  Until some distributions (FreeBSD hear us) change that ...
* Zend extensions are triggered before PHP extensions when a request shows in. That means they got a chance to modify 
  the engine about the current request to come, so that PHP extensions use that modified context. OPCache uses such a 
  trick so that it can perform its complex tasks before any extension had a chance to prevent it to.
* Same for request shutdown : Zend extensions can assume every PHP extension has shut down the request.

My very first simple Zend extension
***********************************

Here we'll detail some hook Zend extensions can use, and what to do with them, in some very simple scenario. Remember 
that Zend extension usually require that you master the Zend engine deeply, so here we'll have a simple starter that 
doesn't make such an assumption.
