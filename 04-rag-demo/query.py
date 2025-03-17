import os
import psycopg2
from openai import OpenAI
from typing import List, Tuple

class RAGQueryEngine:
    def __init__(self):
        self.client = OpenAI(api_key=os.getenv('OPENAI_API_KEY'))
        self.db_params = {
            'host': '127.0.0.1',
            'port': 4566,
            'database': 'dev',
            'user': 'root',
            'password': '',
        }

    def get_relevant_documents(self, question: str) -> List[Tuple[str, str, float]]:
        """Query RisingWave for relevant documents based on embedding similarity."""
        query = """
        WITH question_embedding AS (
            SELECT text_embedding(%s) as embedding
            LIMIT 1
        )
        SELECT 
            d.file_name,
            d.content,
            cosine_similarity(d.embedding, q.embedding) as similarity
        FROM document_embeddings d
        CROSS JOIN question_embedding q
        ORDER BY similarity DESC
        LIMIT 10;
        """
        
        with psycopg2.connect(**self.db_params) as conn:
            with conn.cursor() as cur:
                cur.execute(query, (question,))
                return cur.fetchall()

    def generate_answer(self, question: str, relevant_docs: List[Tuple[str, str, float]]) -> str:
        """Generate an answer using OpenAI's API based on relevant documents."""
        # Prepare context from relevant documents
        context = "\n\n".join([
            f"Document: {doc[0]}\nContent: {doc[1]}\nRelevance: {doc[2]}"
            for doc in relevant_docs
        ])

        # Prepare the prompt
        prompt = f"""Based on the following RisingWave documentation excerpts, please answer this question: {question}

Context:
{context}

Please provide a clear and concise answer based on the provided documentation. If the information is not available in the context, please say so."""

        # Generate response using OpenAI
        response = self.client.chat.completions.create(
            model="gpt-4o",
            messages=[
                {"role": "system", "content": "You are a helpful assistant that answers questions about RisingWave based on the provided documentation."},
                {"role": "user", "content": prompt}
            ],
        )

        return response.choices[0].message.content

def main():
    rag_engine = RAGQueryEngine()
    
    while True:
        question = input("\nEnter your question about RisingWave (or 'quit' to exit): ")
        if question.lower() == 'quit':
            break

        try:
            # Get relevant documents
            print("Searching relevant documents...")
            relevant_docs = rag_engine.get_relevant_documents(question)

            # Print relevant documents
            print("\nRelevant documents:")
            for doc in relevant_docs:
                print(f"- File: {doc[0]} similarity: {doc[2]:.4f}")

            # Generate answer
            print("\nGenerating answer...")
            answer = rag_engine.generate_answer(question, relevant_docs)

            # Print the answer
            print("\nAnswer:")
            print(answer)

        except Exception as e:
            print(f"An error occurred: {str(e)}")

if __name__ == "__main__":
    main()
