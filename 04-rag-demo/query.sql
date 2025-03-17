WITH question_embedding AS (
    SELECT text_embedding('write a Python UDF') as embedding
    LIMIT 1 -- hack
)
SELECT 
    d.file_name,
    -- d.content,
    cosine_similarity(d.embedding, q.embedding) as similarity
FROM document_embeddings d
CROSS JOIN question_embedding q
ORDER BY similarity DESC
LIMIT 10;



SELECT 
    file_name,
    embedding
FROM document_embeddings
where embedding is null;

select
    file_name,
    -- content,
    text_embedding(content) as embedding
from documents
where file_name = './processing/sql/time-windows.mdx';