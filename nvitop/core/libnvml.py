# This file is part of nvitop, the interactive NVIDIA-GPU process viewer.
# License: GNU GPL version 3.

"""Utilities for the NVML Python bindings (`nvidia-ml-py <https://pypi.org/project/nvidia-ml-py>`_)."""

# pylint: disable=invalid-name

import inspect as _inspect
import logging as _logging
import re as _re
import sys as _sys
import threading as _threading
from types import FunctionType as _FunctionType, ModuleType as _ModuleType
from typing import (Tuple as _Tuple, Callable as _Callable, Type as _Type,
                    Union as _Union, Optional as _Optional, Any as _Any)

# Python Bindings for the NVIDIA Management Library (NVML)
# https://pypi.org/project/nvidia-ml-py
import pynvml as _pynvml

from nvitop.core.utils import NA, colored as __colored


__all__ = ['NA', 'nvmlCheckReturn', 'nvmlQuery', 'nvmlInit', 'nvmlInitWithFlags', 'nvmlShutdown', 'NVMLError']


NVMLError = _pynvml.NVMLError
NVMLError.__doc__ = """Base exception class for NVML query errors."""
NVMLError.__new__.__doc__ = """Maps value to a proper subclass of :class:`NVMLError`."""
nvmlExceptionClass = _pynvml.nvmlExceptionClass
nvmlExceptionClass.__doc__ = """Maps value to a proper subclass of :class:`NVMLError`."""

# Load members from module `pynvml` and register them in `__all__`.
_name = _attr = None
_errcode_to_name = {}
# Put error classes in `__all__` first
for _name, _attr in vars(_pynvml).items():
    if _name in ('nvmlInit', 'nvmlInitWithFlags', 'nvmlShutdown'):
        continue
    if _name.startswith('NVML_ERROR_') or _name.startswith('NVMLError_'):
        globals()[_name] = _attr
        __all__.append(_name)
        if _name.startswith('NVML_ERROR_'):
            _errcode_to_name[_attr] = _name
# Then the remaining members
for _name, _attr in vars(_pynvml).items():
    if _name in ('nvmlInit', 'nvmlInitWithFlags', 'nvmlShutdown'):
        continue
    if (
        _name.startswith('NVML_') and not _name.startswith('NVML_ERROR_')
    ) or (
        _name.startswith('nvml') and isinstance(_attr, _FunctionType)
    ):
        globals()[_name] = _attr
        __all__.append(_name)
del _name, _attr

# Add docstring to exception classes
_errcode = _reason = None
for _errcode, _reason in NVMLError._errcode_to_string.items():  # pylint: disable=protected-access
    _subclass = _pynvml.nvmlExceptionClass(_errcode)
    _subclass.__doc__ = '{}. Code: :data:`{}` (:data:`{}`)'.format(_reason.rstrip('.'),
                                                                   _errcode_to_name[_errcode],
                                                                   _errcode)
del _errcode, _reason, _errcode_to_name

# Add explicit references to appease linters
c_nvmlDevice_t = _pynvml.c_nvmlDevice_t
NVMLError_LibraryNotFound = _pynvml.NVMLError_LibraryNotFound  # pylint: disable=no-member
NVMLError_FunctionNotFound = _pynvml.NVMLError_FunctionNotFound  # pylint: disable=no-member


# Module attributes
__flags = []
__initialized = False
__lock = _threading.Lock()

LOGGER = _logging.getLogger(__name__)
UNKNOWN_FUNCTIONS = {}
UNKNOWN_FUNCTIONS_CACHE_SIZE = 1024
VERSIONED_PATTERN = _re.compile(r'^(?P<name>\w+)(?P<suffix>_v(\d)+)$')


def _lazy_init() -> None:
    """Lazily initializes the NVML context."""

    with __lock:
        if __initialized:
            return
    nvmlInit()


def nvmlInit() -> None:
    """Initializes the NVML context with default flag (0).

    Raises:
        NVMLError_LibraryNotFound:
            If cannot find the NVML library, usually the NVIDIA driver is not installed.
        NVMLError_DriverNotLoaded:
            If NVIDIA driver is not loaded.
        NVMLError_LibRmVersionMismatch:
            If RM detects a driver/library version mismatch, usually after an upgrade for NVIDIA
            driver without reloading the kernel module.
        AttributeError:
            If cannot find function :func:`pynvml.nvmlInitWithFlags`, usually the :mod:`pynvml` module
            is overridden by other modules. Need to reinstall package ``nvidia-ml-py``.
    """

    nvmlInitWithFlags(0)


def nvmlInitWithFlags(flags: int) -> None:
    """Initializes the NVML context with the given flags.

    Raises:
        NVMLError_LibraryNotFound:
            If cannot find the NVML library, usually the NVIDIA driver is not installed.
        NVMLError_DriverNotLoaded:
            If NVIDIA driver is not loaded.
        NVMLError_LibRmVersionMismatch:
            If RM detects a driver/library version mismatch, usually after an upgrade for NVIDIA
            driver without reloading the kernel module.
        AttributeError:
            If cannot find function :func:`pynvml.nvmlInitWithFlags`, usually the :mod:`pynvml` module
            is overridden by other modules. Need to reinstall package ``nvidia-ml-py``.
    """

    global __flags, __initialized  # pylint: disable=global-statement,global-variable-not-assigned

    with __lock:
        if len(__flags) > 0 and flags == __flags[-1]:
            __initialized = True
            return

    try:
        _pynvml.nvmlInitWithFlags(flags)
    except NVMLError_LibraryNotFound:
        message = '\n'.join((
            'FATAL ERROR: NVIDIA Management Library (NVML) not found.',
            'HINT: The NVIDIA Management Library ships with the NVIDIA display driver (available at',
            '      https://www.nvidia.com/Download/index.aspx), or can be downloaded as part of the',
            '      NVIDIA CUDA Toolkit (available at https://developer.nvidia.com/cuda-downloads).',
            '      The lists of OS platforms and NVIDIA-GPUs supported by the NVML library can be',
            '      found in the NVML API Reference at https://docs.nvidia.com/deploy/nvml-api.',
        ))
        for text, color, attrs in (('FATAL ERROR:', 'red', ('bold',)),
                                   ('HINT:', 'yellow', ('bold',)),
                                   ('https://www.nvidia.com/Download/index.aspx', None, ('underline',)),
                                   ('https://developer.nvidia.com/cuda-downloads', None, ('underline',)),
                                   ('https://docs.nvidia.com/deploy/nvml-api', None, ('underline',))):
            message = message.replace(text, __colored(text, color=color, attrs=attrs))

        LOGGER.critical(message)
        raise
    except AttributeError:
        message = '\n'.join((
            'FATAL ERROR: The dependency package `nvidia-ml-py` is corrupted. You may have installed',
            '             other packages overriding the module `pynvml`.',
            'Please reinstall `nvitop` with command:',
            '    python3 -m pip install --force-reinstall nvitop',
        ))
        for text, color, attrs in (('FATAL ERROR:', 'red', ('bold',)),
                                   ('nvidia-ml-py', None, ('bold',)),
                                   ('pynvml', None, ('bold',)),
                                   ('nvitop', None, ('bold',))):
            message = message.replace(text, __colored(text, color=color, attrs=attrs), 1)

        LOGGER.critical(message)
        raise
    else:
        with __lock:
            __flags.append(flags)
            __initialized = True


def nvmlShutdown() -> None:
    """Shutdowns the NVML context.

    Raises:
        NVMLError_LibraryNotFound:
            If cannot find the NVML library, usually the NVIDIA driver is not installed.
        NVMLError_DriverNotLoaded:
            If NVIDIA driver is not loaded.
        NVMLError_LibRmVersionMismatch:
            If RM detects a driver/library version mismatch, usually after an upgrade for NVIDIA
            driver without reloading the kernel module.
        NVMLError_Uninitialized:
            If NVML was not first initialized with ``nvmlInit()``.
    """

    global __flags, __initialized  # pylint: disable=global-statement,global-variable-not-assigned

    _pynvml.nvmlShutdown()
    with __lock:
        try:
            __flags.pop()
        except IndexError:
            pass
        __initialized = (len(__flags) > 0)


def nvmlQuery(func: _Union[_Callable[..., _Any], str],
              *args,
              default: _Any = NA,
              ignore_errors: bool = True,
              ignore_function_not_found: bool = False,
              **kwargs) -> _Any:
    """Calls a function with the given arguments from NVML. The NVML context will be automatically
    initialized.

    Args:
        func (Union[Callable[..., Any], str]):
            The function to call. If it is given by string, lookup for the function first from
            module :mod:`pynvml`.
        default (Any):
            The default value if the query fails.
        ignore_errors (bool):
            Whether to ignore errors and return the default value.
        ignore_function_not_found (bool):
            Whether to ignore function not found errors and return the default value. If set to
            :data:`False`, an error message will be logged to the logger.
        *args:
            Positional arguments to pass to the query function.
        **kwargs:
            Keyword arguments to pass to the query function.
    """

    global UNKNOWN_FUNCTIONS  # pylint: disable=global-statement,global-variable-not-assigned

    _lazy_init()

    try:
        if isinstance(func, str):
            try:
                func = getattr(__modself, func)
            except AttributeError as e1:
                raise NVMLError_FunctionNotFound from e1

        retval = func(*args, **kwargs)
    except NVMLError_FunctionNotFound as e2:
        if not ignore_function_not_found:
            if identifier.__name__ == '<lambda>':
                identifier = _inspect.getsource(func)
            else:
                identifier = repr(func)
            with __lock:
                if (
                    identifier not in UNKNOWN_FUNCTIONS
                    and len(UNKNOWN_FUNCTIONS) < UNKNOWN_FUNCTIONS_CACHE_SIZE
                ):
                    UNKNOWN_FUNCTIONS[identifier] = (func, e2)
                    LOGGER.error(
                        'ERROR: A FunctionNotFound error occurred while calling %s.\n'
                        'Please verify whether the `nvidia-ml-py` package is '
                        'compatible with your NVIDIA driver version.',
                        'nvmlQuery({!r}, *args, **kwargs)'.format(func)
                    )
        if ignore_errors or ignore_function_not_found:
            return default
        raise
    except NVMLError:
        if ignore_errors:
            return default
        raise
    else:
        if isinstance(retval, bytes):
            retval = retval.decode('UTF-8')
        return retval


def nvmlCheckReturn(retval: _Any, types: _Optional[_Union[_Type, _Tuple[_Type, ...]]] = None) -> bool:
    """Checks the return value is not :const:`nvitop.NA` and is one of the given types."""

    if types is None:
        return retval != NA
    return retval != NA and isinstance(retval, types)


# Add support for lookup fallback and context manager.
class _CustomModule(_ModuleType):
    """Modified module type to support lookup fallback and context manager.

    Automatic lookup fallback:

        >>> libnvml.c_nvmlGpuInstance_t  # fallback to pynvml.c_nvmlGpuInstance_t
        <class 'pynvml.LP_struct_c_nvmlGpuInstance_t'>

    Context manager:

        >>> with libnvml:
        ...     handle = libnvml.nvmlDeviceGetHandleByIndex(0)
        ... # The NVML context has been shutdown
    """

    def __getattribute__(self, name: str) -> _Union[_Any, _Callable[..., _Any]]:
        """Gets a member from the current module. Fallback to the original package if missing."""

        try:
            return super().__getattribute__(name)
        except AttributeError:
            return getattr(_pynvml, name)

    def __enter__(self) -> '_CustomModule':
        """Entry of the context manager for ``with`` statement."""

        return self

    def __exit__(self, *args, **kwargs) -> None:
        """Shutdowns the NVML context in the context manager for ``with`` statement."""

        self.__del__()

    def __del__(self) -> None:
        """Automatically shutdowns the NVML context on destruction."""

        try:
            nvmlShutdown()
        except NVMLError:
            pass


# Replace entry in sys.modules for this module with an instance of _CustomModule
__modself = _sys.modules[__name__]
__modself.__class__ = _CustomModule
del _CustomModule

del _inspect, _logging, _re, _sys, _threading
del _FunctionType, _ModuleType
del _Tuple, _Callable, _Type, _Union, _Optional, _Any
