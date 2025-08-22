"""
Structured Logging Utilities

Provides JSON logging with request tracking, performance metrics, and security-aware formatting.
Following HX-Infrastructure standards for observability and audit compliance.
"""

import json
import logging
import time
import uuid
from typing import Any, Dict, Optional
from functools import wraps
from fastapi import Request


class StructuredFormatter(logging.Formatter):
    """JSON formatter that masks sensitive data and provides structured output."""
    
    SENSITIVE_KEYS = {'password', 'token', 'key', 'secret', 'auth', 'authorization'}
    
    def format(self, record: logging.LogRecord) -> str:
        log_entry = {
            'timestamp': self.formatTime(record),
            'level': record.levelname,
            'message': record.getMessage(),
            'module': record.module,
            'function': record.funcName,
            'line': record.lineno
        }
        
        # Add extra fields from LogRecord attributes (excluding standard ones)
        standard_attrs = {
            'name', 'msg', 'args', 'levelname', 'levelno', 'pathname', 'filename', 
            'module', 'exc_info', 'exc_text', 'stack_info', 'lineno', 'funcName', 
            'created', 'msecs', 'relativeCreated', 'thread', 'threadName', 
            'processName', 'process', 'taskName', 'getMessage', 'extra'
        }
        extra_fields = {
            key: value for key, value in record.__dict__.items() 
            if key not in standard_attrs and not key.startswith('_')
        }
        if extra_fields:
            log_entry.update(extra_fields)
            
        # Mask sensitive data
        log_entry = self._mask_sensitive_data(log_entry)
        
        return json.dumps(log_entry, default=str)
    
    def _mask_sensitive_data(self, data: Dict[str, Any]) -> Dict[str, Any]:
        """Recursively mask sensitive fields in log data."""
        if isinstance(data, dict):
            return {
                key: self._mask_sensitive_data(value) if not self._is_sensitive_key(key) else "***MASKED***"
                for key, value in data.items()
            }
        elif isinstance(data, list):
            return [self._mask_sensitive_data(item) for item in data]
        else:
            return data
    
    def _is_sensitive_key(self, key: str) -> bool:
        """Check if key contains sensitive information."""
        key_lower = key.lower()
        return any(sensitive in key_lower for sensitive in self.SENSITIVE_KEYS)


def get_structured_logger(name: str) -> logging.Logger:
    """Get a logger configured with structured JSON formatting."""
    logger = logging.getLogger(name)
    
    if not logger.handlers:
        handler = logging.StreamHandler()
        handler.setFormatter(StructuredFormatter())
        logger.addHandler(handler)
        logger.setLevel(logging.INFO)
    
    return logger


def log_request_response(operation: str):
    """Decorator to log request/response with performance metrics and operational data."""
    def decorator(func):
        import inspect
        import asyncio
        
        if inspect.iscoroutinefunction(func) or asyncio.iscoroutinefunction(func):
            # Async wrapper for async functions
            @wraps(func)
            async def async_wrapper(*args, **kwargs):
                logger = get_structured_logger(func.__module__)
                request_id = str(uuid.uuid4())
                start_time = time.time()
                
                # Extract request info if available
                request_info = {}
                namespace = None
                doc_count = 0
                
                for arg in args:
                    if isinstance(arg, Request):
                        request_info = {
                            'method': arg.method,
                            'url': str(arg.url),
                            'client_ip': arg.client.host if arg.client else None,
                            'user_agent': arg.headers.get('user-agent')
                        }
                        break
                
                # Extract operational data from request payload
                for arg in args:
                    if hasattr(arg, 'namespace'):
                        namespace = arg.namespace
                    if hasattr(arg, 'text') and arg.text:
                        doc_count = 1  # Single document
                    if hasattr(arg, 'documents') and arg.documents:
                        doc_count = len(arg.documents)  # Batch documents
                    if hasattr(arg, 'ids') and arg.ids:
                        doc_count = len(arg.ids)  # Delete by IDs
                
                try:
                    logger.info(
                        f"Operation started: {operation}",
                        extra={
                            'request_id': request_id,
                            'operation': operation,
                            'namespace': namespace,
                            'doc_count': doc_count,
                            'event': 'operation_start',
                            **request_info
                        }
                    )
                    
                    result = await func(*args, **kwargs)
                    
                    end_time = time.time()
                    latency_ms = round((end_time - start_time) * 1000, 2)
                    
                    # Extract result data
                    result_info = {}
                    if hasattr(result, 'upserted'):
                        result_info['upserted'] = result.upserted
                    if hasattr(result, 'failed'):
                        result_info['failed'] = result.failed
                    if hasattr(result, 'acknowledged'):
                        result_info['acknowledged'] = result.acknowledged
                    
                    logger.info(
                        f"Operation completed: {operation}",
                        extra={
                            'request_id': request_id,
                            'operation': operation,
                            'namespace': namespace,
                            'doc_count': doc_count,
                            'latency_ms': latency_ms,
                            'event': 'operation_complete',
                            'status': 'success',
                            **result_info
                        }
                    )
                    
                    return result
                    
                except Exception as e:
                    end_time = time.time()
                    latency_ms = round((end_time - start_time) * 1000, 2)
                    
                    logger.error(
                        f"Operation failed: {operation}",
                        extra={
                            'request_id': request_id,
                            'operation': operation,
                            'namespace': namespace,
                            'doc_count': doc_count,
                            'latency_ms': latency_ms,
                            'event': 'operation_error',
                            'status': 'error',
                            'error': str(e),
                            'error_type': type(e).__name__
                        }
                    )
                    raise
            return async_wrapper
        else:
            # Sync wrapper for sync functions
            @wraps(func)
            def sync_wrapper(*args, **kwargs):
                logger = get_structured_logger(func.__module__)
                request_id = str(uuid.uuid4())
                start_time = time.time()
                
                # Extract request info if available
                request_info = {}
                namespace = None
                doc_count = 0
                
                for arg in args:
                    if hasattr(arg, 'method') and hasattr(arg, 'url'):  # Request-like object
                        request_info = {
                            'method': getattr(arg, 'method', None),
                            'url': str(getattr(arg, 'url', '')),
                        }
                        break
                
                # Extract operational data from request payload
                for arg in args:
                    if hasattr(arg, 'namespace'):
                        namespace = arg.namespace
                    if hasattr(arg, 'text') and getattr(arg, 'text', None):
                        doc_count = 1  # Single document
                    if hasattr(arg, 'documents') and getattr(arg, 'documents', None):
                        doc_count = len(arg.documents)  # Batch documents
                    if hasattr(arg, 'ids') and getattr(arg, 'ids', None):
                        doc_count = len(arg.ids)  # Delete by IDs
                
                try:
                    logger.info(
                        f"Operation started: {operation}",
                        extra={
                            'request_id': request_id,
                            'operation': operation,
                            'namespace': namespace,
                            'doc_count': doc_count,
                            'event': 'operation_start',
                            **request_info
                        }
                    )
                    
                    result = func(*args, **kwargs)
                    
                    end_time = time.time()
                    latency_ms = round((end_time - start_time) * 1000, 2)
                    
                    # Extract result data
                    result_info = {}
                    if hasattr(result, 'upserted'):
                        result_info['upserted'] = result.upserted
                    if hasattr(result, 'failed'):
                        result_info['failed'] = result.failed
                    if hasattr(result, 'acknowledged'):
                        result_info['acknowledged'] = result.acknowledged
                    
                    logger.info(
                        f"Operation completed: {operation}",
                        extra={
                            'request_id': request_id,
                            'operation': operation,
                            'namespace': namespace,
                            'doc_count': doc_count,
                            'latency_ms': latency_ms,
                            'event': 'operation_complete',
                            'status': 'success',
                            **result_info
                        }
                    )
                    
                    return result
                    
                except Exception as e:
                    end_time = time.time()
                    latency_ms = round((end_time - start_time) * 1000, 2)
                    
                    logger.error(
                        f"Operation failed: {operation}",
                        extra={
                            'request_id': request_id,
                            'operation': operation,
                            'namespace': namespace,
                            'doc_count': doc_count,
                            'latency_ms': latency_ms,
                            'event': 'operation_error',
                            'status': 'error',
                            'error': str(e),
                            'error_type': type(e).__name__
                        }
                    )
                    raise
            return sync_wrapper
    return decorator


def log_external_call(service: str, operation: str):
    """Decorator to log external service calls with performance tracking."""
    def decorator(func):
        @wraps(func)
        async def wrapper(*args, **kwargs):
            logger = get_structured_logger(func.__module__)
            call_id = str(uuid.uuid4())
            start_time = time.time()
            
            logger.info(
                f"External call started: {service}.{operation}",
                extra={
                    'call_id': call_id,
                    'service': service,
                    'operation': operation,
                    'event': 'external_call_start'
                }
            )
            
            try:
                result = await func(*args, **kwargs)
                
                end_time = time.time()
                latency_ms = round((end_time - start_time) * 1000, 2)
                
                logger.info(
                    f"External call completed: {service}.{operation}",
                    extra={
                        'call_id': call_id,
                        'service': service,
                        'operation': operation,
                        'event': 'external_call_complete',
                        'latency_ms': latency_ms,
                        'result': 'success'
                    }
                )
                
                return result
                
            except Exception as e:
                end_time = time.time()
                latency_ms = round((end_time - start_time) * 1000, 2)
                
                logger.error(
                    f"External call failed: {service}.{operation}",
                    extra={
                        'call_id': call_id,
                        'service': service,
                        'operation': operation,
                        'event': 'external_call_error',
                        'latency_ms': latency_ms,
                        'result': 'error',
                        'error': str(e),
                        'error_type': type(e).__name__
                    }
                )
                raise
                
        return wrapper
    return decorator
