import os
from pydantic import BaseModel, Field
from typing import Optional
from langchain_google_genai import ChatGoogleGenerativeAI
from dotenv import load_dotenv

load_dotenv()

class PropertyExtraction(BaseModel):
    """Pydantic schema for extracting property details from real estate HTML."""
    address: str = Field(description="The full street address of the property.")
    zip_code: str = Field(description="The 5-digit zip code.")
    property_type: str = Field(description="Type of property, e.g., Single-Family, Condo, Multi-Family.")
    roof_type: str = Field(description="Inferred roof type. Usually 'Victorian', 'Flat', 'Pitched', or 'Unknown'.")
    is_hoa: bool = Field(description="True if the property has a Homeowners Association (HOA), else False.")
    is_rental: bool = Field(description="True if the property is explicitly listed as a rental, else False.")

class LLMExtractor:
    def __init__(self):
        # Requires GEMINI_API_KEY to be set in environment variables
        self.llm = ChatGoogleGenerativeAI(
            model="gemini-3.1-pro", # Using the high-tier model for complex HTML parsing
            temperature=0
        )

    def extract_property_details(self, html_content: str) -> PropertyExtraction:
        """
        Uses Gemini to extract structured property details from messy HTML.
        Since HTML can be large, we might need to strip it down, but Gemini has a large context window.
        """
        prompt = f"""
        You are an expert real estate data extraction agent.
        Analyze the following HTML/text from a real estate listing and extract the requested fields.
        If a field is not found, make your best educated guess based on the context (e.g. if the description says 'Victorian', the roof type is likely 'Victorian').
        
        HTML Content:
        {html_content[:50000]} # Truncated for safety, though Gemini handles more.
        """
        
        # In a real LangChain setup, we use structured output binding:
        structured_llm = self.llm.with_structured_output(PropertyExtraction)
        result = structured_llm.invoke(prompt)
        return result
