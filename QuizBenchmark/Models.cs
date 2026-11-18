namespace QuizBenchmark;

public sealed class AnswerItem
{
    public int QuestionId { get; init; }
    public int[] SelectedOptionIds { get; init; } = Array.Empty<int>();
    public bool IsCorrect { get; init; }
    public int TimeSpentSec { get; init; }
}

public sealed class Attempt
{
    public int QuizId { get; init; }
    public int UserId { get; init; }
    public DateTime StartedAt { get; init; }
    public DateTime FinishedAt { get; init; }
    public int DurationSec { get; init; }
    public decimal Score { get; init; }
    public bool Passed { get; init; }
    public List<AnswerItem> Answers { get; init; } = new();
}

public sealed class OptionInfo
{
    public int Id { get; set; }
    public bool IsCorrect { get; set; }
}

public sealed class QuestionInfo
{
    public int Id { get; set; }
    public List<OptionInfo> Options { get; set; } = new();
}

public sealed class QuizInfo
{
    public int Id { get; set; }
    public int PassScore { get; set; }
    public List<QuestionInfo> Questions { get; set; } = new();
}

public sealed class BankRow
{
    public int QuizId { get; set; }
    public int PassScore { get; set; }
    public int QuestionId { get; set; }
    public int OptionId { get; set; }
    public bool IsCorrect { get; set; }
}
