"""
Model Selection Algorithm

Placeholder implementation for routing middleware compatibility.
"""


class ModelSelectionAlgorithm:
    """
    Simple model selection algorithm for routing requests.
    This is a placeholder implementation to satisfy the middleware import.
    """

    def __init__(self):
        pass

    def select_model(self, request_data: dict) -> str:
        """
        Select the appropriate model for the request.

        Args:
            request_data: The request data to analyze

        Returns:
            str: The selected model identifier
        """
        # Default implementation - return a default model
        return "default"

    def get_available_models(self) -> list:
        """
        Get list of available models.

        Returns:
            list: List of available model identifiers
        """
        return ["default"]
