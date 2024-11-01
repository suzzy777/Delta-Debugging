import sys
import pandas as pd
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.metrics.pairwise import cosine_similarity

def load_combined_method_bodies(ground_truth_file, victim, polluter, chunk):
    """Loads the combined method bodies for the victim and polluter and the chunk (cleaner) tests."""
    df = pd.read_csv(ground_truth_file, header=0)  # Load CSV with headers
    print(f"======================", file=sys.stderr)
    print(f"{ground_truth_file}", file=sys.stderr)
    # Extract the victim and polluter method bodies
    victim_row = df[df.iloc[:, 3] == victim]  # victim is in column 3
    polluter_row = df[df.iloc[:, 4] == polluter]  # polluter is in column 4

    if victim_row.empty or polluter_row.empty:
        print(f"Error: Method body not found for victim: {victim} or polluter: {polluter}", file=sys.stderr)
        sys.exit(1)

    victim_body = victim_row.iloc[0, 7]  # Victim method body is in column 7
    polluter_body = polluter_row.iloc[0, 8]  # Polluter method body is in column 8

    # Combine the victim and polluter bodies into a single context
    combined_context = f"{victim_body} {polluter_body}"

    print(f"Chunk received for processing: {chunk}", file=sys.stderr)
    # Extract cleaner (chunk) method bodies
    chunk_bodies = []
    for test in chunk:
        #print(f"TEST in CHUNK:", file=sys.stderr)
        #print(f"{test}", file=sys.stderr)
        test_row = df[df.iloc[:, 5] == test]  # Other tests (chunk) are in column 5
        if not test_row.empty:
            chunk_bodies.append(test_row.iloc[0, 9])  # Method body of each test in the chunk is in column 9
        else:
            print(f"Warning: No method body found for test: {test}", file=sys.stderr)

    if not chunk_bodies:
        print(f"Error: No valid method bodies found for tests in chunk: {chunk}", file=sys.stderr)
        sys.exit(1)

    return combined_context, chunk_bodies

def calculate_tfidf_for_cleaner_with_combined_context(victim, polluter, chunk, ground_truth_file):
    """Calculates TF-IDF similarity between the combined victim+polluter context and each test in the chunk."""
    # Load the combined context and chunk method bodies
    combined_context, chunk_bodies = load_combined_method_bodies(ground_truth_file, victim, polluter, chunk)

    # Create TF-IDF vectors
    vectorizer = TfidfVectorizer()
    tfidf_combined_context = vectorizer.fit_transform([combined_context])  # Vectorize the combined context

    similarities = []
    for chunk_body in chunk_bodies:
        tfidf_chunk = vectorizer.transform([chunk_body])  # Vectorize each chunk body (potential cleaner)
        similarity = cosine_similarity(tfidf_combined_context, tfidf_chunk).flatten()[0]
        similarities.append(similarity)
        print(f"Similarity score for chunk body: {similarity}", file=sys.stderr)


    # Return the average similarity score or 0.0 if no similarities
    if len(similarities) > 0:
        return sum(similarities) / len(similarities)
    return 0.0

    # # Calculate and return the maximum similarity score
    
    # max_similarity = max(similarities) if similarities else 0.0
    # print(f"max similarity score:: {max_similarity}", file=sys.stderr)
    # return max_similarity

if __name__ == "__main__":
    # Read command-line arguments
    ground_truth_file = sys.argv[1]
    victim = sys.argv[2]
    polluter = sys.argv[3]
    chunk = sys.argv[4:]

    # Calculate and print the maximum TF-IDF score
    max_score = calculate_tfidf_for_cleaner_with_combined_context(victim, polluter, chunk, ground_truth_file)
    print(max_score)

