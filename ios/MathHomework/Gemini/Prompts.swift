import Foundation

// Verbatim port of electron/gemini/prompts.ts.
enum Prompts {
    static let transcription = """
    Transcribe this single structured math homework worksheet page. Read every visible printed math problem and the student's handwritten answer in reading order.

    DO NOT SOLVE, CHECK, GRADE, OR EVEN MENTALLY COMPLETE ANY PROBLEM. The expected mathematical answer must not influence what you see. Your job in this pass is visual transcription only.

    CRITICAL HANDWRITING RULES:
    - studentAnswer contains ONLY marks physically handwritten by the student in the answer area.
    - Never copy a printed equals sign, printed digit, problem number, operator, carry mark, or neighboring problem into studentAnswer.
    - First identify the printed problem completely; then inspect the answer area separately.
    - For example, if the page has a printed "=" followed by a handwritten "7", studentAnswer is "7", never "= 7", "17", or "= 17".
    - Use an empty string for a blank answer. Do not guess an unclear digit; lower confidence instead.

    Preserve fractions, decimals, negative signs, operators, and grouping exactly. Use an empty string for a blank answer. Do not invent cropped or unreadable problems. Return only the requested structured result.
    """

    static func verification(firstPassJSON: String) -> String {
        """
        Act as a strict, independent handwriting verifier for this worksheet image. The first-pass transcription JSON is supplied below. Re-inspect the original pixels for every problem in the same array order.

        The most important task is separating pre-printed worksheet content from the student's pencil or pen marks. A printed equals sign or printed digit is never part of studentAnswer. Pay special attention to accidental additions such as reading a handwritten "7" as "17" because a nearby printed vertical stroke was included.

        YOU ARE FORBIDDEN TO SOLVE OR GRADE THE MATH. Do not infer a digit because it would make the equation correct. Treat the mathematically expected answer as unknown. For example, for printed "13 + 4 =" followed by a single handwritten "7", the visual transcription is "7" even though that makes the work wrong.

        Return one verification entry for every supplied problem. Set needsConfirmation=true whenever your studentAnswer differs from the first pass, confidence is below 0.85, the writing overlaps printing, or the mark is genuinely ambiguous. Do not preserve a first-pass reading merely to agree with it.

        FIRST PASS JSON:
        \(firstPassJSON)
        """
    }
}
