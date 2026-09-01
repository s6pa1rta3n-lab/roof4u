import os
import json
import re
from typing import Optional, List, Dict, Any, Union
from datetime import datetime
from pydantic import BaseModel, Field, field_validator
import openai
from dotenv import load_dotenv

load_dotenv()

DEFAULT_LOCAL_URL = "http://localhost:8000/v1"
DEFAULT_LOCAL_MODEL = "nvidia/llama-3.1-nemotron-70b-instruct"
DEFAULT_API_KEY = "not-needed"


class PropertyExtraction(BaseModel):
    """Pydantic schema for extracting property details from real estate HTML/text via local LLM."""
    address: str = Field(description="The full street address of the property.")
    zip_code: str = Field(description="The 5-digit zip code.")
    property_type: Optional[str] = Field(default="Single-Family", description="Type of property, e.g. Single-Family, Condo, Multi-Family.")
    roof_type: Optional[str] = Field(default="Unknown", description="Inferred roof type: 'Victorian', 'Flat', 'Pitched', 'Mansard', or 'Unknown'.")
    is_hoa: Optional[bool] = Field(default=False, description="True if the property has a Homeowners Association (HOA), else False.")
    is_rental: Optional[bool] = Field(default=False, description="True if the property is explicitly listed as a rental, else False.")
    estimated_value: Optional[float] = Field(default=None, description="Estimated market value or listing price in USD.")
    bedrooms: Optional[int] = Field(default=None, description="Number of bedrooms.")
    bathrooms: Optional[float] = Field(default=None, description="Number of bathrooms.")
    sqft: Optional[int] = Field(default=None, description="Total square footage.")
    year_built: Optional[int] = Field(default=None, description="Year the property was built.")
    description: Optional[str] = Field(default=None, description="Summary or architectural description.")
    confidence_score: Optional[float] = Field(default=1.0, description="Extraction confidence between 0.0 and 1.0.")

    @field_validator("zip_code", mode="before")
    @classmethod
    def format_zip(cls, v: Any) -> str:
        if v is None:
            return ""
        s = str(v).strip()
        m = re.search(r"\b\d{5}\b", s)
        return m.group(0) if m else s


class PermitRecord(BaseModel):
    """Schema for individual permit records."""
    permit_number: Optional[str] = Field(default=None, description="Permit identification number.")
    permit_type: Optional[str] = Field(default=None, description="Type of permit (e.g. Reroof, Alteration, Electrical).")
    description: Optional[str] = Field(default=None, description="Description of the permit scope.")
    issued_date: Optional[str] = Field(default=None, description="Date the permit was issued (YYYY-MM-DD or string).")
    status: Optional[str] = Field(default=None, description="Permit status (e.g. Completed, Issued, Expired).")


class CountyPermitExtraction(BaseModel):
    """Pydantic schema for extracting assessor and permit data from municipal portals."""
    address: str = Field(description="The full street address of the property.")
    apn: Optional[str] = Field(default=None, description="Assessor's Parcel Number (APN / Block and Lot).")
    owner_name: Optional[str] = Field(default=None, description="Property owner name or LLC.")
    assessed_value: Optional[float] = Field(default=None, description="Total assessed tax value in USD.")
    last_roof_permit_date: Optional[str] = Field(default=None, description="Date of the most recent roofing permit.")
    permit_history: List[Union[PermitRecord, Dict[str, Any], str]] = Field(
        default_factory=list,
        description="Historical list of building and roofing permits."
    )
    roof_age_years: Optional[float] = Field(default=None, description="Estimated age of roof in years based on permit history.")
    is_hoa: Optional[bool] = Field(default=False, description="True if property is classified as condo / HOA.")
    is_rental: Optional[bool] = Field(default=False, description="True if recorded as rental / multi-unit commercial.")
    confidence_score: Optional[float] = Field(default=1.0, description="Extraction confidence between 0.0 and 1.0.")


class LocalLLMExtractor:
    """
    Local LLM-powered extraction engine for real estate and municipal permit documents.
    Communicates with local OpenAI-compatible inference endpoints (e.g., vLLM, Ollama, NVIDIA NIM).
    """
    def __init__(
        self,
        base_url: Optional[str] = None,
        model: Optional[str] = None,
        api_key: Optional[str] = None,
        timeout: float = 30.0
    ):
        self.base_url = base_url or os.getenv("LOCAL_INFERENCE_URL", DEFAULT_LOCAL_URL)
        self.model = model or os.getenv("LOCAL_MODEL_NAME", DEFAULT_LOCAL_MODEL)
        self.api_key = api_key or os.getenv("LOCAL_API_KEY", DEFAULT_API_KEY)
        self.timeout = timeout

        self.client = openai.OpenAI(
            base_url=self.base_url,
            api_key=self.api_key,
            timeout=self.timeout
        )

    def _clean_json_response(self, text: str) -> str:
        """
        Strips thinking tokens (<think>...</think>), markdown codeblocks,
        and isolates genuine JSON payload even if preamble contains curly braces.
        """
        if not text:
            return ""
        text = text.strip()

        # 1. Remove thinking / reasoning tags (<think>...</think>, <thought>...</thought>)
        text = re.sub(r"<think(?:ing)?>.*?</think(?:ing)?>", "", text, flags=re.DOTALL | re.IGNORECASE)
        text = re.sub(r"<thought>.*?</thought>", "", text, flags=re.DOTALL | re.IGNORECASE)
        text = text.strip()

        # 2. Check fenced codeblocks ```json ... ``` or ``` ... ```
        code_blocks = re.findall(r"```(?:json)?\s*([\s\S]*?)\s*```", text)
        for block in code_blocks:
            block_clean = block.strip()
            if block_clean.startswith("{") and block_clean.endswith("}"):
                try:
                    json.loads(block_clean)
                    return block_clean
                except Exception:
                    pass

        # 3. Balanced brace scanner to find valid JSON object
        length = len(text)
        for start_idx in range(length):
            if text[start_idx] != "{":
                continue
            depth = 0
            in_string = False
            escape = False
            for i in range(start_idx, length):
                char = text[i]
                if in_string:
                    if escape:
                        escape = False
                    elif char == "\\":
                        escape = True
                    elif char == '"':
                        in_string = False
                else:
                    if char == '"':
                        in_string = True
                    elif char == "{":
                        depth += 1
                    elif char == "}":
                        depth -= 1
                        if depth == 0:
                            candidate = text[start_idx:i+1].strip()
                            try:
                                json.loads(candidate)
                                return candidate
                            except Exception:
                                break

        # 4. Fallback: if markdown fences exist, strip outer fences
        if text.startswith("```"):
            lines = text.split("\n")
            if lines[0].startswith("```"):
                lines = lines[1:]
            if lines and lines[-1].startswith("```"):
                lines = lines[:-1]
            text = "\n".join(lines).strip()

        # 5. Fallback: find first '{' and last '}'
        start = text.find("{")
        end = text.rfind("}")
        if start != -1 and end != -1 and end > start:
            return text[start:end+1].strip()

        return text


    def _call_model(self, system_prompt: str, user_content: str) -> str:
        """Sends chat completion request to the local model endpoint."""
        try:
            response = self.client.chat.completions.create(
                model=self.model,
                messages=[
                    {"role": "system", "content": system_prompt},
                    {"role": "user", "content": user_content}
                ],
                temperature=0.0,
                response_format={"type": "json_object"}
            )
            content = response.choices[0].message.content
            if not content:
                raise ValueError("Received empty content from local model endpoint.")
            return content
        except Exception as e:
            raise RuntimeError(f"Local LLM inference failed: {e}") from e

    def extract_property_details(self, html_or_text: str) -> PropertyExtraction:
        """
        Extracts structured property details from preprocessed real estate HTML or text.
        Returns a validated PropertyExtraction instance.
        """
        system_prompt = (
            "You are an expert real estate data extraction engine. "
            "Analyze the provided property text/HTML and return ONLY a valid JSON object matching this schema:\n"
            "{\n"
            '  "address": "string (full street address)",\n'
            '  "zip_code": "string (5-digit zip)",\n'
            '  "property_type": "string (Single-Family, Condo, Multi-Family, Townhouse)",\n'
            '  "roof_type": "string (Victorian, Flat, Pitched, Mansard, Unknown)",\n'
            '  "is_hoa": boolean,\n'
            '  "is_rental": boolean,\n'
            '  "estimated_value": number or null,\n'
            '  "bedrooms": integer or null,\n'
            '  "bathrooms": number or null,\n'
            '  "sqft": integer or null,\n'
            '  "year_built": integer or null,\n'
            '  "description": "string summary or null",\n'
            '  "confidence_score": number (0.0 to 1.0)\n'
            "}\n"
            "If a field cannot be determined, provide appropriate defaults (e.g. roof_type='Unknown', is_hoa=false)."
        )

        user_content = f"Property Listing Content:\n\n{html_or_text[:16000]}"
        raw_response = self._call_model(system_prompt, user_content)
        cleaned_json = self._clean_json_response(raw_response)

        try:
            return PropertyExtraction.model_validate_json(cleaned_json)
        except Exception as e:
            # Attempt to parse json dict and coerce
            try:
                data = json.loads(cleaned_json)
                return PropertyExtraction.model_validate(data)
            except Exception:
                raise ValueError(f"Failed to validate PropertyExtraction schema: {e}\nRaw output: {raw_response}") from e

    def extract_county_permit_details(self, html_or_text: str) -> CountyPermitExtraction:
        """
        Extracts structured assessor parcel numbers, assessed values, and permit histories.
        Returns a validated CountyPermitExtraction instance.
        """
        system_prompt = (
            "You are an expert municipal and county assessor data extraction engine. "
            "Analyze the provided assessor/permit records HTML or text and return ONLY a valid JSON object matching this schema:\n"
            "{\n"
            '  "address": "string (full street address)",\n'
            '  "apn": "string or null (Assessor Parcel Number / Block and Lot)",\n'
            '  "owner_name": "string or null",\n'
            '  "assessed_value": number or null,\n'
            '  "last_roof_permit_date": "string (YYYY-MM-DD or year) or null",\n'
            '  "permit_history": [\n'
            '    {"permit_number": "string", "permit_type": "string", "description": "string", "issued_date": "string", "status": "string"}\n'
            "  ],\n"
            '  "roof_age_years": number or null,\n'
            '  "is_hoa": boolean,\n'
            '  "is_rental": boolean,\n'
            '  "confidence_score": number (0.0 to 1.0)\n'
            "}\n"
            "Calculate roof_age_years if last_roof_permit_date or installation date is present."
        )

        user_content = f"Assessor & Permit Portal Content:\n\n{html_or_text[:16000]}"
        raw_response = self._call_model(system_prompt, user_content)
        cleaned_json = self._clean_json_response(raw_response)

        try:
            return CountyPermitExtraction.model_validate_json(cleaned_json)
        except Exception as e:
            try:
                data = json.loads(cleaned_json)
                return CountyPermitExtraction.model_validate(data)
            except Exception:
                raise ValueError(f"Failed to validate CountyPermitExtraction schema: {e}\nRaw output: {raw_response}") from e


# Backward compatibility alias
LLMExtractor = LocalLLMExtractor
