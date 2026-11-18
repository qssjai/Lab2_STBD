using Dapper;
using Npgsql;

namespace QuizBenchmark;

public static class Setup
{
    public static async Task EnsureStudentsAsync(string connectionString, int target)
    {
        await using var conn = new NpgsqlConnection(connectionString);
        await conn.OpenAsync();

        int roleId = await conn.ExecuteScalarAsync<int>("SELECT id FROM v_roles WHERE name = 'student'");
        var existingEmails = (await conn.QueryAsync<string>("SELECT email FROM v_active_users")).ToHashSet();
        int studentCount = await conn.ExecuteScalarAsync<int>(
            "SELECT COUNT(*) FROM v_active_users WHERE role_name = 'student'");

        int i = 1;
        while (studentCount < target)
        {
            string email = $"bench{i}@bench.ua";
            string lastName = $"Тестовий{i}";
            i++;

            if (existingEmails.Contains(email))
                continue;

            await conn.ExecuteScalarAsync<int>(
                "CALL sp_create_user(@email, @hash, @first, @last, @role, @actor, @id)",
                new
                {
                    email,
                    hash = "bench_hash",
                    first = "Студент",
                    last = lastName,
                    role = roleId,
                    actor = (int?)null,
                    id = (int?)null
                });

            studentCount++;
        }
    }

    public static async Task<int[]> LoadStudentIdsAsync(string connectionString)
    {
        await using var conn = new NpgsqlConnection(connectionString);
        var ids = await conn.QueryAsync<int>(
            "SELECT id FROM v_active_users WHERE role_name = 'student' ORDER BY id");
        return ids.ToArray();
    }

    public static async Task<List<QuizInfo>> LoadQuizBankAsync(string connectionString)
    {
        await using var conn = new NpgsqlConnection(connectionString);

        var rows = await conn.QueryAsync<BankRow>(@"
            SELECT q.id AS quiz_id,
                   q.pass_score,
                   qq.id AS question_id,
                   qo.id AS option_id,
                   qo.is_correct
            FROM quizzes q
            JOIN quiz_questions qq ON qq.quiz_id = q.id
            JOIN quiz_options   qo ON qo.question_id = qq.id
            ORDER BY q.id, qq.id, qo.id");

        return rows
            .GroupBy(r => r.QuizId)
            .Select(quiz => new QuizInfo
            {
                Id = quiz.Key,
                PassScore = quiz.First().PassScore,
                Questions = quiz
                    .GroupBy(r => r.QuestionId)
                    .Select(question => new QuestionInfo
                    {
                        Id = question.Key,
                        Options = question
                            .Select(o => new OptionInfo { Id = o.OptionId, IsCorrect = o.IsCorrect })
                            .ToList()
                    })
                    .ToList()
            })
            .ToList();
    }
}
