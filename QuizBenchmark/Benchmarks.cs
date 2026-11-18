using System.Diagnostics;
using System.Globalization;
using System.Text.Json;
using Dapper;
using MongoDB.Bson;
using MongoDB.Driver;
using Npgsql;

namespace QuizBenchmark;

internal sealed class FullRow
{
    public long AttemptId { get; set; }
    public int QuizId { get; set; }
    public int UserId { get; set; }
    public DateTime StartedAt { get; set; }
    public DateTime FinishedAt { get; set; }
    public int DurationSec { get; set; }
    public decimal Score { get; set; }
    public bool Passed { get; set; }
    public long AnswerId { get; set; }
    public int QuestionId { get; set; }
    public bool IsCorrect { get; set; }
    public int TimeSpentSec { get; set; }
    public int[] SelectedOptionIds { get; set; } = Array.Empty<int>();
}

internal sealed class SummaryRow
{
    public long AttemptId { get; set; }
    public int QuizId { get; set; }
    public int UserId { get; set; }
    public DateTime StartedAt { get; set; }
    public DateTime FinishedAt { get; set; }
    public int DurationSec { get; set; }
    public decimal Score { get; set; }
    public bool Passed { get; set; }
}

public sealed class Benchmarks
{
    private sealed record Variant(string Label, Func<int, Task> Action);

    private sealed record Result(string Scenario, string Label, int Runs,
        double MedianMs, double P95Ms, double MeanMs);

    private readonly string _pgConnectionString;
    private readonly IMongoDatabase _database;
    private readonly IMongoCollection<BsonDocument> _mongo;
    private readonly List<Result> _results = new();
    private NpgsqlConnection _pg = null!;

    public Benchmarks(string pgConnectionString, string mongoConnectionString)
    {
        _pgConnectionString = pgConnectionString;

        var settings = MongoClientSettings.FromConnectionString(mongoConnectionString);
        settings.ServerSelectionTimeout = TimeSpan.FromSeconds(5);
        var client = new MongoClient(settings);

        _database = client.GetDatabase("course_management_nosql");
        _mongo = _database.GetCollection<BsonDocument>("quiz_attempts");
    }

    public async Task RunAsync()
    {
        await using var pg = new NpgsqlConnection(_pgConnectionString);
        await pg.OpenAsync();
        _pg = pg;

        long attemptsCount = await pg.ExecuteScalarAsync<long>("SELECT COUNT(*) FROM v_attempt_summary");
        long mongoCount = await _mongo.CountDocumentsAsync(FilterDefinition<BsonDocument>.Empty);

        if (attemptsCount == 0 || attemptsCount != mongoCount)
        {
            Console.WriteLine($"Дані в базах не збігаються або порожні (PostgreSQL: {attemptsCount}, MongoDB: {mongoCount}).");
            Console.WriteLine("Спершу завантажте дані пунктом 1, 2 або 3.");
            return;
        }

        Console.WriteLine();
        Console.WriteLine($"Тести швидкодії на {attemptsCount:N0} спробах");
        Console.WriteLine("Підготовка параметрів запитів...");

        long maxId = await pg.ExecuteScalarAsync<long>("SELECT MAX(attempt_id) FROM v_attempt_summary");
        var mongoIds = (await _mongo.Find(FilterDefinition<BsonDocument>.Empty)
                .Project(new BsonDocument("_id", 1)).ToListAsync())
            .Select(d => d["_id"]).ToList();
        int[] userIds = (await pg.QueryAsync<int>(
            "SELECT DISTINCT user_id FROM v_attempt_summary ORDER BY user_id")).ToArray();

        var random = new Random(1);
        const int maxIterations = 1000;
        long[] pgAttemptIds = Enumerable.Range(0, maxIterations)
            .Select(_ => 1L + random.NextInt64(maxId)).ToArray();
        BsonValue[] mongoAttemptIds = Enumerable.Range(0, maxIterations)
            .Select(_ => mongoIds[random.Next(mongoIds.Count)]).ToArray();
        int[] randomUsers = Enumerable.Range(0, maxIterations)
            .Select(_ => userIds[random.Next(userIds.Length)]).ToArray();

        // 1. читання однієї спроби з усіма відповідями
        await RunScenarioAsync("1. Читання спроби за id з усіма відповідями", 50, 300,
            new Variant("PostgreSQL (v_attempt_full)", async i =>
            {
                await _pg.QueryAsync<FullRow>(
                    "SELECT * FROM v_attempt_full WHERE attempt_id = @id",
                    new { id = pgAttemptIds[i] });
            }),
            new Variant("MongoDB (find за _id)", async i =>
            {
                await _mongo.Find(new BsonDocument("_id", mongoAttemptIds[i])).FirstOrDefaultAsync();
            }));

        // 2. останні 20 спроб студента з усіма відповідями
        await RunScenarioAsync("2. Останні 20 спроб студента з відповідями", 50, 300,
            new Variant("PostgreSQL (IN, без оптимізації)", async i =>
            {
                await _pg.QueryAsync<FullRow>(@"
                    SELECT f.* FROM v_attempt_full f
                    WHERE f.attempt_id IN (
                        SELECT attempt_id FROM v_attempt_summary
                        WHERE user_id = @userId
                        ORDER BY started_at DESC
                        LIMIT 20)",
                    new { userId = randomUsers[i] });
            }),
            new Variant("PostgreSQL (LATERAL)", async i =>
            {
                await _pg.QueryAsync<FullRow>(@"
                    SELECT f.*
                    FROM (SELECT attempt_id FROM v_attempt_summary
                          WHERE user_id = @userId
                          ORDER BY started_at DESC
                          LIMIT 20) s
                    CROSS JOIN LATERAL (
                        SELECT * FROM v_attempt_full WHERE attempt_id = s.attempt_id) f",
                    new { userId = randomUsers[i] });
            }),
            new Variant("PostgreSQL (функція + LATERAL)", async i =>
            {
                await _pg.QueryAsync<FullRow>(@"
                    SELECT s.attempt_id, s.quiz_id, s.user_id, s.started_at, s.finished_at,
                           s.duration_sec, s.score, s.passed,
                           a.answer_id, a.question_id, a.is_correct, a.time_spent_sec,
                           a.selected_option_ids
                    FROM (SELECT * FROM v_attempt_summary
                          WHERE user_id = @userId
                          ORDER BY started_at DESC
                          LIMIT 20) s
                    CROSS JOIN LATERAL fn_attempt_answers(s.attempt_id) a",
                    new { userId = randomUsers[i] });
            }),
            new Variant("MongoDB (find + sort + limit)", async i =>
            {
                await _mongo.Find(new BsonDocument("userId", randomUsers[i]))
                    .Sort(new BsonDocument("startedAt", -1))
                    .Limit(20)
                    .ToListAsync();
            }));

        await RunScenarioAsync("3. Останні 20 спроб студента без відповідей", 50, 300,
            new Variant("PostgreSQL (v_attempt_summary)", async i =>
            {
                await _pg.QueryAsync<SummaryRow>(@"
                    SELECT * FROM v_attempt_summary
                    WHERE user_id = @userId
                    ORDER BY started_at DESC
                    LIMIT 20",
                    new { userId = randomUsers[i] });
            }),
            new Variant("MongoDB (проєкція без answers)", async i =>
            {
                await _mongo.Find(new BsonDocument("userId", randomUsers[i]))
                    .Sort(new BsonDocument("startedAt", -1))
                    .Limit(20)
                    .Project<BsonDocument>(new BsonDocument("answers", 0))
                    .ToListAsync();
            }));

        var quizStatsPipeline = PipelineDefinition<BsonDocument, BsonDocument>.Create(new[]
        {
            new BsonDocument("$group", new BsonDocument
            {
                { "_id", "$quizId" },
                { "attempts", new BsonDocument("$sum", 1) },
                { "avgScore", new BsonDocument("$avg", "$score") },
                { "passed", new BsonDocument("$sum",
                    new BsonDocument("$cond", new BsonArray { "$passed", 1, 0 })) },
                { "avgDuration", new BsonDocument("$avg", "$durationSec") }
            })
        });

        await RunScenarioAsync("4. Агрегація: статистика по тестах (усі спроби)", 2, 7,
            new Variant("PostgreSQL (v_quiz_stats)", async _ =>
            {
                await _pg.QueryAsync("SELECT * FROM v_quiz_stats");
            }),
            new Variant("MongoDB ($group)", async _ =>
            {
                await _mongo.Aggregate<BsonDocument>(quizStatsPipeline,
                    new AggregateOptions { AllowDiskUse = true }).ToListAsync();
            }));

        var questionStatsPipeline = PipelineDefinition<BsonDocument, BsonDocument>.Create(new[]
        {
            new BsonDocument("$unwind", "$answers"),
            new BsonDocument("$group", new BsonDocument
            {
                { "_id", "$answers.questionId" },
                { "answers", new BsonDocument("$sum", 1) },
                { "correct", new BsonDocument("$sum",
                    new BsonDocument("$cond", new BsonArray { "$answers.isCorrect", 1, 0 })) },
                { "avgTime", new BsonDocument("$avg", "$answers.timeSpentSec") }
            }),
            new BsonDocument("$project", new BsonDocument
            {
                { "avgTime", 1 },
                { "correctRate", new BsonDocument("$multiply",
                    new BsonArray { 100, new BsonDocument("$divide", new BsonArray { "$correct", "$answers" }) }) }
            }),
            new BsonDocument("$sort", new BsonDocument("correctRate", 1)),
            new BsonDocument("$limit", 10)
        });

        await RunScenarioAsync("5. Агрегація: 10 найскладніших питань (усі відповіді)", 1, 5,
            new Variant("PostgreSQL (v_question_stats)", async _ =>
            {
                await _pg.QueryAsync(
                    "SELECT * FROM v_question_stats ORDER BY correct_rate ASC LIMIT 10");
            }),
            new Variant("MongoDB ($unwind + $group)", async _ =>
            {
                await _mongo.Aggregate<BsonDocument>(questionStatsPipeline,
                    new AggregateOptions { AllowDiskUse = true }).ToListAsync();
            }));

        await RunInsertScenarioAsync(maxId);

        await PrintSizesAsync();
        SaveCsv(attemptsCount);
    }

    private async Task RunInsertScenarioAsync(long maxIdBefore)
    {
        const int warmup = 30;
        const int runs = 300;

        var bank = await Setup.LoadQuizBankAsync(_pgConnectionString);
        int[] students = await Setup.LoadStudentIdsAsync(_pgConnectionString);
        var generator = new DataGenerator(bank, students, seed: 777);

        var attempts = Enumerable.Range(0, warmup + runs).Select(_ => generator.Next()).ToList();
        var jsons = attempts.Select(ToJson).ToList();
        var docsDefault = attempts.Select(MongoLoader.ToDocument).ToList();
        var docsJournal = attempts.Select(MongoLoader.ToDocument).ToList();
        var docsNoJournal = attempts.Select(MongoLoader.ToDocument).ToList();

        var journaled = _mongo.WithWriteConcern(WriteConcern.W1.With(journal: true));
        var noJournal = _mongo.WithWriteConcern(WriteConcern.W1.With(journal: false));

        await RunScenarioAsync("6. Вставка однієї спроби", warmup, runs,
            new Variant("PostgreSQL (sp_save_quiz_attempt)", async i =>
            {
                await _pg.ExecuteScalarAsync<long>(
                    "CALL sp_save_quiz_attempt(CAST(@data AS jsonb), @id)",
                    new { data = jsons[i], id = (long?)null });
            }),
            new Variant("MongoDB (за замовчуванням)", async i =>
            {
                await _mongo.InsertOneAsync(docsDefault[i]);
            }),
            new Variant("MongoDB (w:1, з журналом)", async i =>
            {
                await journaled.InsertOneAsync(docsJournal[i]);
            }),
            new Variant("MongoDB (w:1, без журналу)", async i =>
            {
                await noJournal.InsertOneAsync(docsNoJournal[i]);
            }));

        await _pg.ExecuteAsync("DELETE FROM quiz_attempts WHERE id > @maxId", new { maxId = maxIdBefore });

        var insertedIds = docsDefault.Concat(docsJournal).Concat(docsNoJournal).Select(d => d["_id"]);
        await _mongo.DeleteManyAsync(new BsonDocument("_id",
            new BsonDocument("$in", new BsonArray(insertedIds))));
    }

    private async Task RunScenarioAsync(string name, int warmup, int runs, params Variant[] variants)
    {
        Console.WriteLine();
        Console.WriteLine($"{name} (прогрів {warmup}, замірів {runs})");

        foreach (var variant in variants)
        {
            for (int i = 0; i < warmup; i++)
                await variant.Action(i);

            var times = new double[runs];
            for (int i = 0; i < runs; i++)
            {
                long start = Stopwatch.GetTimestamp();
                await variant.Action(warmup + i);
                times[i] = Stopwatch.GetElapsedTime(start).TotalMilliseconds;
            }

            Array.Sort(times);
            double median = runs % 2 == 1
                ? times[runs / 2]
                : (times[runs / 2 - 1] + times[runs / 2]) / 2;
            double p95 = times[(int)Math.Ceiling(runs * 0.95) - 1];
            double mean = times.Average();

            _results.Add(new Result(name, variant.Label, runs, median, p95, mean));

            Console.WriteLine(
                $"  {variant.Label,-34} медіана {median,10:F2} мс   p95 {p95,10:F2} мс   середнє {mean,10:F2} мс");
        }
    }

    private async Task PrintSizesAsync()
    {
        long pgTables = await _pg.ExecuteScalarAsync<long>(@"
            SELECT COALESCE(SUM(pg_table_size(t)), 0)::bigint
            FROM unnest(ARRAY['quiz_attempts', 'attempt_answers', 'attempt_answer_options']::regclass[]) AS t");
        long pgIndexes = await _pg.ExecuteScalarAsync<long>(@"
            SELECT COALESCE(SUM(pg_indexes_size(t)), 0)::bigint
            FROM unnest(ARRAY['quiz_attempts', 'attempt_answers', 'attempt_answer_options']::regclass[]) AS t");

        var stats = await _database.RunCommandAsync(
            new BsonDocumentCommand<BsonDocument>(new BsonDocument("collStats", "quiz_attempts")));
        long mongoRaw = stats["size"].ToInt64();
        long mongoStorage = stats["storageSize"].ToInt64();
        long mongoIndexes = stats["totalIndexSize"].ToInt64();

        Console.WriteLine();
        Console.WriteLine("Розмір на диску");
        Console.WriteLine($"  PostgreSQL: дані {Mb(pgTables)}, індекси {Mb(pgIndexes)}, разом {Mb(pgTables + pgIndexes)}");
        Console.WriteLine($"  MongoDB:    дані {Mb(mongoStorage)} (без стиснення {Mb(mongoRaw)}), індекси {Mb(mongoIndexes)}, разом {Mb(mongoStorage + mongoIndexes)}");
    }

    private static string Mb(long bytes) =>
        (bytes / 1024.0 / 1024.0).ToString("F1", CultureInfo.CurrentCulture) + " МБ";

    private void SaveCsv(long attemptsCount)
    {
        string path = Path.Combine(AppContext.BaseDirectory, $"benchmark_results_{attemptsCount}.csv");

        var lines = new List<string> { "scenario;variant;runs;median_ms;p95_ms;mean_ms" };
        foreach (var r in _results)
        {
            lines.Add(string.Join(';',
                r.Scenario, r.Label, r.Runs,
                r.MedianMs.ToString("F3", CultureInfo.InvariantCulture),
                r.P95Ms.ToString("F3", CultureInfo.InvariantCulture),
                r.MeanMs.ToString("F3", CultureInfo.InvariantCulture)));
        }

        File.WriteAllLines(path, lines);

        Console.WriteLine();
        Console.WriteLine($"Результати збережено у файл: {path}");
    }

    private static string ToJson(Attempt a) => JsonSerializer.Serialize(new
    {
        quizId = a.QuizId,
        userId = a.UserId,
        startedAt = a.StartedAt.ToString("yyyy-MM-ddTHH:mm:ss", CultureInfo.InvariantCulture),
        finishedAt = a.FinishedAt.ToString("yyyy-MM-ddTHH:mm:ss", CultureInfo.InvariantCulture),
        durationSec = a.DurationSec,
        score = a.Score,
        passed = a.Passed,
        answers = a.Answers.Select(x => new
        {
            questionId = x.QuestionId,
            selectedOptionIds = x.SelectedOptionIds,
            isCorrect = x.IsCorrect,
            timeSpentSec = x.TimeSpentSec
        })
    });
}
