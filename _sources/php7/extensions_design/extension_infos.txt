Publishing extension informations
=================================

Extensions can publish informations asked by ``phpinfo()`` or the Reflection API. Let's see that together.

This chapter won't be too long as there is really no difficulty.

MINFO() hook
------------

Everything takes place in the ``MINFO()`` hook you declared, if you declared one.  If you declared none, then the engine 
will run a default function to print informations about your extension. That function will only print the version of 
your extension and the :doc:`INI entries <ini_settings>` you eventually declared. If you want to hook into such 
process, you must declare an ``MINFO()`` :doc:`hook <php_lifecycle>` in your extension structure.

.. note:: Everything takes place in `ext/standard/info.c <https://github.com/php/php-src/blob/
          ce64b82ebb2ac87e53cb85c312eafc8c5c37b112/ext/standard/info.c>`_ , you may read that file. Printing 
          information about PHP extensions is done by the engine by calling `php_info_print_module() 
          <https://github.com/php/php-src/blob/ce64b82ebb2ac87e53cb85c312eafc8c5c37b112/ext/standard/info.c#L139>`_

Here is a simple ``MINFO()`` example::

    #include "php/main/SAPI.h"
    #include "ext/standard/info.h"

    #define PIB_TXT  "PHPInternalsBook Authors"
    #define PIB_HTML "<h3>" PIB_TXT "</h3>"

    PHP_MINFO_FUNCTION(pib)
    {
        time_t t;
        char cur_time[32];

        time(&t);
        php_asctime_r(localtime(&t), cur_time);

        php_info_print_table_start();
            php_info_print_table_colspan_header(2, "PHPInternalsBook");
            php_info_print_table_row(2, "Current time", cur_time);
        php_info_print_table_end();

        php_info_print_box_start(0);
            if (!sapi_module.phpinfo_as_text) {
                php_write(PIB_HTML, strlen(PIB_HTML));
            } else {
                php_write(PIB_TXT, strlen(PIB_TXT));
            }
        php_info_print_box_end();
    }

    zend_module_entry pib_module_entry = {
        STANDARD_MODULE_HEADER,
        "pib",
        NULL, /* Function entries */
        NULL, /* Module init */
        NULL, /* Module shutdown */
        NULL, /* Request init */
        NULL, /* Request shutdown */
        PHP_MINFO(pib), /* Module information */
        "0.1", /* Replace with version number for your extension */
        STANDARD_MODULE_PROPERTIES
    };

.. image:: ./images/php_minfo.png
   :align: center

What you basically have to do is to deal with ``php_info_print_*()`` API, that allows to print into the output stream 
that is generated. If you want to print some raw informations, a simple ``php_write()`` is enough. ``php_write()`` just 
writes what you pass as argument onto the SAPI output stream, whereas ``php_info_print_*()`` API does as well, but 
before formats the content using HTML *table-tr-td* tags if the output is expected to be HTML, or simple spaces if not.

Like you can see, you need to include *ext/standard/info.h* to access the ``php_info_print_*()`` API, and you will need 
*php/main/SAPI.h* to access the ``sapi_module`` symbol. That symbol is global, it represents the current *SAPI* used by 
the PHP process. The ``phpinfo_as_text`` field inform if you are going to write in a "Web" SAPI like *php-fpm* f.e, or 
in a "text" one, like *php-cli*.

What will trigger your ``MINFO()`` hook are :

* Calls to userland ``phpinfo()`` function
* ``php -i``, ``php-cgi -i``, ``php-fpm -i``. More generaly ``<SAPI_binary> - i``
* ``php --ri`` or userland ``ReflectionExtension::info()``

.. note:: Take care of the output formating. Probe for ``sapi_module.phpinfo_as_text`` if you need to change between 
          text and HTML formatting. You don't know how your extensions' infos will be called by userland.

If you need to display your INI settings, just call for the ``DISPLAY_INI_ENTRIES()`` macro into your ``MINFO()``. This 
macro resolves to `display_ini_entries() 
<https://github.com/php/php-src/blob/4903f044d3a65de5b1c457d9eb618c9e247f7086/main/php_ini.c#L167>`_.

A note about the Reflection API
-------------------------------

The Reflection heavily uses your ``zend_module_entry`` structure. For example, when you call 
``ReflectionExtension::getVersion()``, the API just reads the version field of your ``zend_module_entry`` structure.

Same to discover functions, your ``zend_module_entry`` has got a ``const struct _zend_function_entry *functions`` member 
which is used to register PHP functions.

Basically, the PHP userland Reflection API just reads your ``zend_module_entry`` structure and publishes those 
informations. It may also use your ``module_number`` to gather back informations your extension registered at different 
locations against the engine. For example, ``ReflectionExtension::getINIentries()`` or 
``ReflectionExtension::getClasses()`` use this.
