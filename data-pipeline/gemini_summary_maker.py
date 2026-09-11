from google import genai
from dotenv import load_dotenv
import time
from pydantic import BaseModel, Field
from typing import List


class Event(BaseModel):
    global_event_id: int = Field(
        description =
            "The GDELT GlobalEventID of the event being summarised. Copy it EXACTLY "
            "as given in the input block. Never invent an ID, never alter one, and "
            "never merge two events into one object. Every event in the input must "
            "appear exactly once in the output."
    )
    ai_evidence_quality: int = Field(
        description =
            "How well the supplied article headlines actually describe THIS specific "
            "event. You are grading the HEADLINES, not the importance of the event. "
            "0 = NONE: headlines are unrelated to the event, or are website boilerplate "
            "(newsletter, privacy policy, section index). "
            "1 = WEAK: only a vague topical or geographic overlap; the event itself is "
            "not visible in them. "
            "2 = MEDIUM: same topic, actors and place, but the specific incident cannot "
            "be pinned down (e.g. generic 'war latest updates' roundups). "
            "3 = GOOD: most headlines clearly describe this event, though some detail "
            "is missing. "
            "4 = GREAT: the headlines unambiguously and consistently describe this "
            "exact event."
    )
    ai_summary: str = Field(
        description =
            "One sentence (max 300 characters) stating what actually happened, in "
            "neutral English news style. Use ONLY the structured record and the "
            "headlines supplied for THIS event. Never use information from another "
            "event in the batch, and never add outside knowledge. If ai_evidence_quality "
            "is 0 or 1, do not guess: state plainly that the sources do not identify "
            "what happened."
    )

class EventsList(BaseModel):
    sumlist: List[Event] = Field(
        description="One object per event in the input batch, in the same order."
    )


def get_summary(top_events_data):

    load_dotenv()
    client = genai.Client()

    start = time.time()

    PROMPT = f"""
        You are a news analyst. You will receive a batch of world events detected by GDELT.

        For each event you get two things:

        1. A STRUCTURED RECORD extracted by GDELT — who did what to whom, where, and how it
        scored. Treat these fields as reliable facts.

        2. ARTICLE HEADLINES — taken from the URLs of news articles that mention the event.
        They come from URL "slugs", so they are lowercase and dash-separated. Read them as
        headlines: "border-poll-conditions-have-to-be-discussed-taoiseach-says" means the
        headline "Border poll conditions have to be discussed, Taoiseach says".

        CRITICAL: a headline is NOT guaranteed to be about the event. GDELT extracts one event
        per sentence, so an article can mention an event in passing while its headline is about
        something completely different. Some headlines will be website boilerplate. Your job is
        to identify the event that the structured record describes AND that the headlines
        corroborate.

        Rules:
        - Treat every event independently. NEVER use headlines or facts from one event when
        writing about another, even if they look related.
        - Use only what is given. Do not add background, dates, casualty figures, names or
        outcomes that are not in the input.
        - Prefer what MOST headlines agree on. A single outlying headline is noise.
        - If the headlines do not identify the event, say so. Do not fill the gap with a
        plausible-sounding guess. A summary that admits ignorance is correct output; an
        invented one is a failure.
        - Return exactly one object per input event, with event_id copied verbatim.

        Here is the batch:
        {top_events_data}
    """

    interaction = client.interactions.create(
        model="gemini-3.5-flash-lite",
        input=PROMPT,
        response_format={
            "type": "text",
            "mime_type": "application/json",
            "schema": EventsList.model_json_schema()
        },
    )

    end = time.time()
    print(f"AI summary took {end - start} sec")

    return interaction.output_text