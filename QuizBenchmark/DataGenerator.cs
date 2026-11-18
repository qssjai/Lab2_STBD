namespace QuizBenchmark;

public sealed class DataGenerator
{
    private const int PeriodSeconds = 600 * 24 * 3600;
    private static readonly DateTime BaseDate = new(2025, 1, 1);

    private readonly Random _random;
    private readonly List<QuizInfo> _quizzes;
    private readonly int[] _userIds;

    public DataGenerator(List<QuizInfo> quizzes, int[] userIds, int seed)
    {
        _quizzes = quizzes;
        _userIds = userIds;
        _random = new Random(seed);
    }

    public Attempt Next()
    {
        var quiz = _quizzes[_random.Next(_quizzes.Count)];
        int userId = _userIds[_random.Next(_userIds.Length)];
        DateTime startedAt = BaseDate.AddSeconds(_random.Next(PeriodSeconds));

        var answers = new List<AnswerItem>(quiz.Questions.Count);
        int correctAnswers = 0;
        int totalTime = 0;

        foreach (var question in quiz.Questions)
        {
            var correct = question.Options.Where(o => o.IsCorrect).Select(o => o.Id).ToList();
            var wrong = question.Options.Where(o => !o.IsCorrect).Select(o => o.Id).ToList();

            var selected = new List<int>();
            int roll = _random.Next(100);

            if (roll < 70)
            {
                selected.AddRange(correct);
            }
            else if (roll < 90 && wrong.Count > 0)
            {
                selected.Add(wrong[_random.Next(wrong.Count)]);
            }
            else
            {
                selected.AddRange(correct);
                if (wrong.Count > 0)
                    selected.Add(wrong[_random.Next(wrong.Count)]);
            }

            if (selected.Count == 0)
                selected.Add(question.Options[0].Id);

            selected.Sort();

            bool isCorrect = selected.Count == correct.Count && !selected.Except(correct).Any();
            int timeSpent = _random.Next(5, 91);

            if (isCorrect)
                correctAnswers++;
            totalTime += timeSpent;

            answers.Add(new AnswerItem
            {
                QuestionId = question.Id,
                SelectedOptionIds = selected.ToArray(),
                IsCorrect = isCorrect,
                TimeSpentSec = timeSpent
            });
        }

        decimal score = Math.Round(100m * correctAnswers / quiz.Questions.Count, 2);

        return new Attempt
        {
            QuizId = quiz.Id,
            UserId = userId,
            StartedAt = startedAt,
            FinishedAt = startedAt.AddSeconds(totalTime),
            DurationSec = totalTime,
            Score = score,
            Passed = score >= quiz.PassScore,
            Answers = answers
        };
    }
}
