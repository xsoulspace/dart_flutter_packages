/// Keyword extraction, stopword filtering, and relevance ranking for
/// projection.
///
/// This is the seam to swap for embedding-based retrieval later: everything
/// downstream ([rankFragments], [keywordsOf]) is deterministic and
/// LLM-free per the North Star; an embedding indexer would only replace how
/// keywords are derived and matched.
library;

/// Common English stopwords excluded from keyword indexing/ranking — without
/// this, terms like "the" match every beat and one accidental hit beats
/// genuine relevance in the score.
const stopwords = {
  'the',
  'and',
  'for',
  'are',
  'but',
  'not',
  'you',
  'all',
  'can',
  'her',
  'was',
  'one',
  'our',
  'out',
  'day',
  'get',
  'has',
  'him',
  'his',
  'how',
  'man',
  'new',
  'now',
  'old',
  'see',
  'two',
  'way',
  'who',
  'its',
  'did',
  'that',
  'this',
  'with',
  'have',
  'from',
  'they',
  'will',
  'would',
  'there',
  'their',
  'what',
  'about',
  'which',
  'when',
  'make',
  'like',
  'time',
  'just',
  'know',
  'take',
  'into',
  'your',
  'than',
  'then',
  'them',
  'these',
  'some',
  'could',
  'other',
  'been',
  'more',
  'also',
  'may',
  'should',
  'does',
};

/// Split [text] into lowercase keywords, dropping stopwords and short terms.
List<String> keywordsOf(String text) => text
    .toLowerCase()
    .split(RegExp(r'\W+'))
    .where((t) => t.length > 2 && !stopwords.contains(t))
    .toList();
