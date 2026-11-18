using System.Diagnostics;
using System.Text;
using Dapper;
using Npgsql;

namespace QuizBenchmark;

internal static class Program
{
    private const string PgConnectionString =
        "Host=localhost;Port=5432;Database=course_management;Username=postgres;Password=041006;Command Timeout=300";

    private const string MongoConnectionString = "mongodb://localhost:27017";

    private const int StudentsCount = 1000;
    private const int BatchSize = 5000;

    private static async Task Main()
    {
        Console.OutputEncoding = Encoding.UTF8;
        DefaultTypeMap.MatchNamesWithUnderscores = true;

        while (true)
        {
            Console.WriteLine();
            Console.WriteLine("Завантаження спроб проходження тестів в обидві бази");
            Console.WriteLine("  1. 10 000 спроб");
            Console.WriteLine("  2. 100 000 спроб");
            Console.WriteLine("  3. 300 000 спроб");
            Console.WriteLine("  4. Тести швидкодії (на завантажених даних)");
            Console.WriteLine("  0. Вихід");
            Console.Write("Ваш вибір: ");

            string? choice = Console.ReadLine()?.Trim();

            int total = choice switch
            {
                "1" => 10_000,
                "2" => 100_000,
                "3" => 300_000,
                _ => 0
            };

            if (choice != "4" && total == 0)
                break;

            try
            {
                if (choice == "4")
                    await new Benchmarks(PgConnectionString, MongoConnectionString).RunAsync();
                else
                    await LoadAsync(total);
            }
            catch (PostgresException ex)
            {
                Console.WriteLine();
                Console.WriteLine($"Помилка PostgreSQL: {ex.MessageText}");
            }
            catch (Exception ex)
            {
                Console.WriteLine();
                Console.WriteLine($"Помилка: {ex.Message}");
            }
        }
    }

    private static async Task LoadAsync(int total)
    {
        Console.WriteLine();
        Console.WriteLine("Підготовка: студенти та банк тестів...");

        await Setup.EnsureStudentsAsync(PgConnectionString, StudentsCount);
        int[] userIds = await Setup.LoadStudentIdsAsync(PgConnectionString);
        var bank = await Setup.LoadQuizBankAsync(PgConnectionString);

        Console.WriteLine($"Студентів: {userIds.Length}, тестів у банку: {bank.Count}");

        var generator = new DataGenerator(bank, userIds, seed: 42);
        var mongo = new MongoLoader(MongoConnectionString);

        await using var pg = new PostgresLoader(PgConnectionString);
        await pg.ResetAsync();
        await mongo.ResetAsync();

        TimeSpan pgTime = TimeSpan.Zero;
        TimeSpan mongoTime = TimeSpan.Zero;

        for (int done = 0; done < total; done += BatchSize)
        {
            int size = Math.Min(BatchSize, total - done);

            var batch = new List<Attempt>(size);
            for (int i = 0; i < size; i++)
                batch.Add(generator.Next());

            var sw = Stopwatch.StartNew();
            await pg.LoadBatchAsync(batch);
            pgTime += sw.Elapsed;

            sw.Restart();
            await mongo.LoadBatchAsync(batch);
            mongoTime += sw.Elapsed;

            Console.Write($"\rЗавантажено {done + size:N0} з {total:N0}");
        }

        await pg.FinalizeAsync();
        Console.WriteLine();

        await PrintResultAsync(total, pgTime, mongoTime, mongo);
    }

    private static async Task PrintResultAsync(int total, TimeSpan pgTime, TimeSpan mongoTime, MongoLoader mongo)
    {
        await using var conn = new NpgsqlConnection(PgConnectionString);
        long pgAttempts = await conn.ExecuteScalarAsync<long>("SELECT COUNT(*) FROM v_attempt_summary");
        long pgAnswers = await conn.ExecuteScalarAsync<long>("SELECT COUNT(*) FROM attempt_answers");
        long pgOptions = await conn.ExecuteScalarAsync<long>("SELECT COUNT(*) FROM attempt_answer_options");
        long mongoAttempts = await mongo.CountAsync();

        Console.WriteLine();
        Console.WriteLine($"Результат завантаження {total:N0} спроб");
        Console.WriteLine(new string('-', 60));
        Console.WriteLine($"PostgreSQL (COPY, 3 таблиці): {pgTime.TotalSeconds,7:F1} с, {total / pgTime.TotalSeconds,9:F0} спроб/с");
        Console.WriteLine($"MongoDB (InsertMany)        : {mongoTime.TotalSeconds,7:F1} с, {total / mongoTime.TotalSeconds,9:F0} спроб/с");
        Console.WriteLine(new string('-', 60));
        Console.WriteLine($"Рядків у PostgreSQL: спроб {pgAttempts:N0}, відповідей {pgAnswers:N0}, обраних варіантів {pgOptions:N0}");
        Console.WriteLine($"Документів у MongoDB: {mongoAttempts:N0}");
    }
}
