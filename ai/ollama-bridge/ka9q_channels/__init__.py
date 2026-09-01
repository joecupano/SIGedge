"""ka9q_channels — read-only channel presentation layer for LLM tool use.

Provider-agnostic on purpose: ollama_tools.py wraps these functions for
Ollama's tools= API today; an MCP server can wrap the same functions
tomorrow with zero changes here. See ../README.md.
"""
