import sys
import pandas as pd
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.metrics.pairwise import cosine_similarity


def load_test_method_bodies(ground_truth_file, victim, chunk):
    """Loads the method bodies for the victim and chunk tests."""
    # Load the CSV file with headers
    df = pd.read_csv(ground_truth_file, header=0)  # Ensure headers are properly handled

    # Extract the victim's method body (column 6) by matching victim (column 3)
    victim_row = df[df.iloc[:, 3] == victim]
    if victim_row.empty:
        print(f"Error: No method body found for victim: {victim}", file=sys.stderr)
        sys.exit(1)
    victim_body = victim_row.iloc[0, 6]  # Extract first match's body

    # Extract chunk tests' method bodies (column 7) by matching p_or_np (column 4)
    chunk_bodies = []
    for test in chunk:
        # Debug output redirected to stderr, including the test name
        print(f"Processing test in the chunk: {test}", file=sys.stderr)
        test_row = df[df.iloc[:, 4] == test]
        if not test_row.empty:
            chunk_bodies.append(test_row.iloc[0, 7])  # Extract first match's body
        else:
            print(f"Warning: No method body found for test: {test}", file=sys.stderr)

    if not chunk_bodies:
        print(f"Error: No valid method bodies found for tests in chunk: {chunk}", file=sys.stderr)
        sys.exit(1)

    return victim_body, chunk_bodies

def calculate_tfidf_avg(victim, chunk, ground_truth_file):
    """Calculates the average TF-IDF similarity between the victim and chunk tests."""
    # Load the method bodies
    victim_body, chunk_bodies = load_test_method_bodies(ground_truth_file, victim, chunk)

    # Create TF-IDF vectors
    vectorizer = TfidfVectorizer()
    tfidf_chunk = vectorizer.fit_transform(chunk_bodies)
    tfidf_victim = vectorizer.transform([victim_body])

    # Calculate cosine similarities
    similarities = cosine_similarity(tfidf_victim, tfidf_chunk).flatten()

    # Return the average similarity score or 0.0 if no similarities
    if similarities.size > 0:
        return sum(similarities) / len(similarities)
    return 0.0

if __name__ == "__main__":
    # Read command-line arguments
    ground_truth_file = sys.argv[1]
    victim = sys.argv[2]
    chunk = sys.argv[3:]

    # Calculate and print the average TF-IDF score
    avg_score = calculate_tfidf_avg(victim, chunk, ground_truth_file)
    print(avg_score)
