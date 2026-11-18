using MongoDB.Bson;
using MongoDB.Driver;

namespace QuizBenchmark;

public sealed class MongoLoader
{
    private const string CollectionName = "quiz_attempts";

    private const string SchemaJson = @"{
        bsonType: 'object',
        required: ['quizId', 'userId', 'startedAt', 'finishedAt',
                   'durationSec', 'score', 'passed', 'answers'],
        properties: {
            quizId:      { bsonType: 'number' },
            userId:      { bsonType: 'number' },
            startedAt:   { bsonType: 'date' },
            finishedAt:  { bsonType: 'date' },
            durationSec: { bsonType: 'number', minimum: 0 },
            score:       { bsonType: 'number', minimum: 0, maximum: 100 },
            passed:      { bsonType: 'bool' },
            answers: {
                bsonType: 'array',
                items: {
                    bsonType: 'object',
                    required: ['questionId', 'selectedOptionIds', 'isCorrect', 'timeSpentSec'],
                    properties: {
                        questionId:        { bsonType: 'number' },
                        selectedOptionIds: { bsonType: 'array', items: { bsonType: 'number' } },
                        isCorrect:         { bsonType: 'bool' },
                        timeSpentSec:      { bsonType: 'number', minimum: 0 }
                    }
                }
            }
        }
    }";

    private readonly IMongoDatabase _database;
    private readonly IMongoCollection<BsonDocument> _collection;

    public MongoLoader(string connectionString)
    {
        var settings = MongoClientSettings.FromConnectionString(connectionString);
        settings.ServerSelectionTimeout = TimeSpan.FromSeconds(5);

        var client = new MongoClient(settings);
        _database = client.GetDatabase("course_management_nosql");
        _collection = _database.GetCollection<BsonDocument>(CollectionName);
    }

    public async Task ResetAsync()
    {
        await _database.DropCollectionAsync(CollectionName);

        var options = new CreateCollectionOptions<BsonDocument>
        {
            Validator = new BsonDocumentFilterDefinition<BsonDocument>(
                new BsonDocument("$jsonSchema", BsonDocument.Parse(SchemaJson)))
        };
        await _database.CreateCollectionAsync(CollectionName, options);

        await _collection.Indexes.CreateManyAsync(new[]
        {
            new CreateIndexModel<BsonDocument>(new BsonDocument { { "userId", 1 }, { "startedAt", -1 } }),
            new CreateIndexModel<BsonDocument>(new BsonDocument("quizId", 1)),
            new CreateIndexModel<BsonDocument>(new BsonDocument("answers.questionId", 1))
        });
    }

    public Task LoadBatchAsync(List<Attempt> batch)
    {
        var documents = batch.Select(ToDocument).ToList();
        return _collection.InsertManyAsync(documents, new InsertManyOptions { IsOrdered = false });
    }

    public Task<long> CountAsync() =>
        _collection.CountDocumentsAsync(FilterDefinition<BsonDocument>.Empty);

    public static BsonDocument ToDocument(Attempt attempt)
    {
        return new BsonDocument
        {
            { "quizId", attempt.QuizId },
            { "userId", attempt.UserId },
            { "startedAt", DateTime.SpecifyKind(attempt.StartedAt, DateTimeKind.Utc) },
            { "finishedAt", DateTime.SpecifyKind(attempt.FinishedAt, DateTimeKind.Utc) },
            { "durationSec", attempt.DurationSec },
            { "score", (double)attempt.Score },
            { "passed", attempt.Passed },
            {
                "answers",
                new BsonArray(attempt.Answers.Select(a => new BsonDocument
                {
                    { "questionId", a.QuestionId },
                    { "selectedOptionIds", new BsonArray(a.SelectedOptionIds) },
                    { "isCorrect", a.IsCorrect },
                    { "timeSpentSec", a.TimeSpentSec }
                }))
            }
        };
    }
}
