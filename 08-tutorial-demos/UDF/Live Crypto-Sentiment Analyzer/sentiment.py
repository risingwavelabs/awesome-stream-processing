# 1. Import necessary libraries
from arrow_udf import udf, UdfServer
from nltk.sentiment.vader import SentimentIntensityAnalyzer
import nltk

# 2. Download VADER lexicon (do this once on startup)
nltk.download('vader_lexicon', quiet=True)

# Initialize the analyzer globally so we don't reload it per row
sid = SentimentIntensityAnalyzer()

# 3. Define the Batched UDF
# input_types: matches the SQL input (VARCHAR)
# result_type: matches the SQL output (DOUBLE PRECISION)
# batch=True: Crucial! Receives a List[str] instead of a single str.
@udf(input_types=["VARCHAR"], result_type="DOUBLE PRECISION", batch=True)
def get_sentiment(headlines: list[str]) -> list[float]:
    scores = []
    for headline in headlines:
        if headline is None:
            scores.append(0.0)
            continue
        # Get the 'compound' score (-1 to 1)
        score = sid.polarity_scores(str(headline))['compound']
        scores.append(score)
    return scores

if __name__ == '__main__':
    # 4. Start the UDF Server
    # RisingWave will connect to this port
    server = UdfServer(location="0.0.0.0:8815")
    server.add_function(get_sentiment)
    print("Starting Sentiment UDF Server on port 8815...")
    server.serve()