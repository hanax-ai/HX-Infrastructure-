#!/usr/bin/env python3
"""
Cosine similarity calculator for embedding vectors.
Accepts three JSON arrays as arguments and prints cosine similarities.
"""
import sys
import json
import math

def cosine_similarity(vec1, vec2):
    """Calculate cosine similarity between two vectors."""
    dot_product = sum(a * b for a, b in zip(vec1, vec2))
    norm1 = math.sqrt(sum(a * a for a in vec1)) or 1.0
    norm2 = math.sqrt(sum(b * b for b in vec2)) or 1.0
    return dot_product / (norm1 * norm2)

if __name__ == "__main__":
    if len(sys.argv) != 4:
        print("Usage: cosine_similarity.py <vec1_json> <vec2_json> <vec3_json>", file=sys.stderr)
        sys.exit(1)
    
    try:
        vec1 = json.loads(sys.argv[1])
        vec2 = json.loads(sys.argv[2])
        vec3 = json.loads(sys.argv[3])
        
        cos_12 = cosine_similarity(vec1, vec2)
        cos_13 = cosine_similarity(vec1, vec3)
        
        print(f"{cos_12:.6f} {cos_13:.6f}")
        
    except (json.JSONDecodeError, ValueError) as e:
        print(f"Error processing vectors: {e}", file=sys.stderr)
        sys.exit(1)
