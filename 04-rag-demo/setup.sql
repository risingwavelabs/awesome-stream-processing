create function text_embedding(t varchar) returns real[] language javascript as $$
    export async function text_embedding(t) {
        for (let retries = 0; retries < 3; retries++) {
            try {
                const response = await fetch("https://api.openai.com/v1/embeddings", {
                    method: 'POST',
                    headers: {
                        'Authorization': `Bearer <your-openai-api-key>`,
                        'Content-Type': 'application/json'
                    },
                    body: JSON.stringify({
                        input: t,
                        model: "text-embedding-3-small"
                    })
                });

                if (!response.ok) {
                    const error = await response.json();
                    throw new Error(`OpenAI API error: ${error.error?.message || 'Unknown error'}`);
                }

                const data = await response.json();
                return data.data[0].embedding;
            } catch (error) {
            }
        }
        return null;
    }
$$ WITH (
    async = true,
    batch = false
);

create function cosine_similarity(v1 real[], v2 real[]) returns real language rust as $$
    fn cosine_similarity(a: &[f32], b: &[f32]) -> f32 {
        let dot_product: f32 = a.iter().zip(b).map(|(a, b)| a * b).sum();
        let norm_a: f32 = a.iter().map(|a| a * a).sum();
        let norm_b: f32 = b.iter().map(|b| b * b).sum();
        dot_product / (norm_a * norm_b).sqrt()
    }
$$;

create table documents (
    file_name varchar,
    content text,
    primary key (file_name)
);

create materialized view document_embeddings as
with t as (
    select
        *, text_embedding(content) as embedding
    from documents
)
select
    file_name,
    content,
    embedding
from t
where embedding is not null;

