import os
import json
import time
from openai import OpenAI

# the newest OpenAI model is "gpt-4o" which was released May 13, 2024.
# do not change this unless explicitly requested by the user
openai = OpenAI(api_key=os.environ.get("OPENAI_API_KEY"))

def verify_referral(user_data):
    """
    Verify a referral using OpenAI's GPT-4 model.
    
    Args:
        user_data (dict): Data about the referral including user activity,
                         interaction patterns, and timing
    
    Returns:
        dict: Verification result including:
            - verified (bool): Whether the referral appears legitimate
            - confidence (float): Confidence score between 0 and 1
            - reasoning (str): Explanation of the verification decision
    """
    try:
        prompt = f"""
        Analyze this referral for potential fraud or spam:
        User Activity: {json.dumps(user_data.get('activity', {}), indent=2)}
        Time Patterns: {json.dumps(user_data.get('timing', {}), indent=2)}
        Interaction Data: {json.dumps(user_data.get('interactions', {}), indent=2)}

        Determine if this is a legitimate referral by analyzing:
        1. Activity patterns suggesting real user engagement
        2. Natural timing distribution of actions
        3. Interaction patterns between referrer and referred user

        Respond with a JSON object containing:
        {
            "verified": boolean,
            "confidence": float between 0 and 1,
            "reasoning": "detailed explanation"
        }
        """

        response = openai.chat.completions.create(
            model="gpt-4o",
            messages=[
                {
                    "role": "system",
                    "content": "You are a referral verification expert. Analyze the given data and detect fraudulent or spam referrals."
                },
                {"role": "user", "content": prompt}
            ],
            response_format={"type": "json_object"}
        )

        result = json.loads(response.choices[0].message.content)
        
        # Add metadata about the verification process
        result["timestamp"] = str(int(time.time()))
        result["model_version"] = "gpt-4o"
        
        return result

    except Exception as e:
        raise Exception(f"Failed to verify referral: {str(e)}")
