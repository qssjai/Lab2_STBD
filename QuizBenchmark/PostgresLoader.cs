using System.Data;
using Dapper;
using Npgsql;
using NpgsqlTypes;

namespace QuizBenchmark;

public sealed class PostgresLoader : IAsyncDisposable
{
    private readonly NpgsqlConnection _connection;
    private long _nextAttemptId = 1;
    private long _nextAnswerId = 1;

    public PostgresLoader(string connectionString)
    {
        _connection = new NpgsqlConnection(connectionString);
    }

    public async Task ResetAsync()
    {
        if (_connection.State != ConnectionState.Open)
            await _connection.OpenAsync();

        await _connection.ExecuteAsync(
            "TRUNCATE quiz_attempts, attempt_answers, attempt_answer_options RESTART IDENTITY");

        _nextAttemptId = 1;
        _nextAnswerId = 1;
    }

    public async Task LoadBatchAsync(List<Attempt> batch)
    {
        await using (var writer = await _connection.BeginBinaryImportAsync(
            "COPY quiz_attempts (id, quiz_id, user_id, started_at, finished_at, duration_sec, score, passed) " +
            "FROM STDIN (FORMAT BINARY)"))
        {
            long attemptId = _nextAttemptId;
            foreach (var attempt in batch)
            {
                await writer.StartRowAsync();
                await writer.WriteAsync(attemptId, NpgsqlDbType.Bigint);
                await writer.WriteAsync(attempt.QuizId, NpgsqlDbType.Integer);
                await writer.WriteAsync(attempt.UserId, NpgsqlDbType.Integer);
                await writer.WriteAsync(attempt.StartedAt, NpgsqlDbType.Timestamp);
                await writer.WriteAsync(attempt.FinishedAt, NpgsqlDbType.Timestamp);
                await writer.WriteAsync(attempt.DurationSec, NpgsqlDbType.Integer);
                await writer.WriteAsync(attempt.Score, NpgsqlDbType.Numeric);
                await writer.WriteAsync(attempt.Passed, NpgsqlDbType.Boolean);
                attemptId++;
            }
            await writer.CompleteAsync();
        }

        await using (var writer = await _connection.BeginBinaryImportAsync(
            "COPY attempt_answers (id, attempt_id, question_id, is_correct, time_spent_sec) " +
            "FROM STDIN (FORMAT BINARY)"))
        {
            long answerId = _nextAnswerId;
            long attemptId = _nextAttemptId;
            foreach (var attempt in batch)
            {
                foreach (var answer in attempt.Answers)
                {
                    await writer.StartRowAsync();
                    await writer.WriteAsync(answerId, NpgsqlDbType.Bigint);
                    await writer.WriteAsync(attemptId, NpgsqlDbType.Bigint);
                    await writer.WriteAsync(answer.QuestionId, NpgsqlDbType.Integer);
                    await writer.WriteAsync(answer.IsCorrect, NpgsqlDbType.Boolean);
                    await writer.WriteAsync(answer.TimeSpentSec, NpgsqlDbType.Integer);
                    answerId++;
                }
                attemptId++;
            }
            await writer.CompleteAsync();
        }

        long optionAnswerId = _nextAnswerId;
        await using (var writer = await _connection.BeginBinaryImportAsync(
            "COPY attempt_answer_options (answer_id, option_id) FROM STDIN (FORMAT BINARY)"))
        {
            foreach (var attempt in batch)
            {
                foreach (var answer in attempt.Answers)
                {
                    foreach (int optionId in answer.SelectedOptionIds)
                    {
                        await writer.StartRowAsync();
                        await writer.WriteAsync(optionAnswerId, NpgsqlDbType.Bigint);
                        await writer.WriteAsync(optionId, NpgsqlDbType.Integer);
                    }
                    optionAnswerId++;
                }
            }
            await writer.CompleteAsync();
        }

        _nextAttemptId += batch.Count;
        _nextAnswerId = optionAnswerId;
    }

    public async Task FinalizeAsync()
    {
        await _connection.ExecuteAsync(
            "SELECT setval(pg_get_serial_sequence('quiz_attempts', 'id'), " +
            "GREATEST((SELECT MAX(id) FROM quiz_attempts), 1))");
        await _connection.ExecuteAsync(
            "SELECT setval(pg_get_serial_sequence('attempt_answers', 'id'), " +
            "GREATEST((SELECT MAX(id) FROM attempt_answers), 1))");

        await _connection.ExecuteAsync("ANALYZE quiz_attempts");
        await _connection.ExecuteAsync("ANALYZE attempt_answers");
        await _connection.ExecuteAsync("ANALYZE attempt_answer_options");
    }

    public async ValueTask DisposeAsync()
    {
        await _connection.DisposeAsync();
    }
}
