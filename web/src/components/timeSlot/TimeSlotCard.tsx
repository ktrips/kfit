import React from 'react';
import {
  TimeSlot,
  TimeSlotGoal,
  TimeSlotProgress,
  TIME_SLOT_INFO,
  calculateCompletionRate,
  isFullyCompleted
} from '../../types/timeSlot';

interface TimeSlotCardProps {
  timeSlot: TimeSlot;
  goal: TimeSlotGoal;
  progress: TimeSlotProgress;
  onEdit: () => void;
  onAddMindfulness?: () => void;
  onAddStretch?: () => void;
  onToggleCustomActivity?: (activityId: string) => void;
}

const TimeSlotCard: React.FC<TimeSlotCardProps> = ({
  timeSlot,
  goal,
  progress,
  onEdit,
  onAddMindfulness,
  onAddStretch,
  onToggleCustomActivity
}) => {
  const info = TIME_SLOT_INFO[timeSlot];
  const completionRate = calculateCompletionRate(progress, goal);
  const isComplete = isFullyCompleted(progress, goal);

  const logGoalsCount =
    (goal.logGoal.mealRequired ? 1 : 0) +
    (goal.logGoal.drinkRequired ? 1 : 0) +
    (goal.logGoal.mindInputRequired ? 1 : 0);

  const logCompletedCount =
    (progress.logProgress.mealLogged ? 1 : 0) +
    (progress.logProgress.drinkLogged ? 1 : 0) +
    (progress.logProgress.mindInputLogged ? 1 : 0);

  return (
    <div className="duo-card p-6">
      {/* Header */}
      <div className="flex items-center justify-between mb-4">
        <div className="flex items-center space-x-3">
          <span className="text-3xl">{info.emoji}</span>
          <div>
            <h3 className="text-xl font-black text-duo-dark">
              {info.displayName}
            </h3>
            <p className="text-sm text-duo-gray font-bold">{info.timeRange}</p>
          </div>
        </div>

        {/* Completion Circle */}
        <div className="relative w-12 h-12">
          <svg className="w-12 h-12 transform -rotate-90">
            <circle
              cx="24"
              cy="24"
              r="20"
              stroke="#E5E7EB"
              strokeWidth="4"
              fill="none"
            />
            <circle
              cx="24"
              cy="24"
              r="20"
              stroke={isComplete ? '#10B981' : '#F59E0B'}
              strokeWidth="4"
              fill="none"
              strokeDasharray={`${2 * Math.PI * 20}`}
              strokeDashoffset={`${
                2 * Math.PI * 20 * (1 - completionRate)
              }`}
              strokeLinecap="round"
            />
          </svg>
          <div className="absolute inset-0 flex items-center justify-center">
            <span
              className={`text-xs font-bold ${
                isComplete ? 'text-green-600' : 'text-amber-600'
              }`}
            >
              {Math.round(completionRate * 100)}%
            </span>
          </div>
        </div>
      </div>

      <div className="border-t border-gray-200 pt-4 space-y-3">
        {/* Training Goal */}
        <GoalRow
          icon="💪"
          label="トレーニング"
          current={progress.trainingCompleted}
          goal={goal.trainingGoal}
          color="green"
        />

        {/* Mindfulness Goal */}
        <GoalRow
          icon="🧘"
          label="マインドフルネス"
          current={progress.mindfulnessCompleted}
          goal={goal.mindfulnessGoal}
          color="purple"
          actionLabel="+1"
          onAction={onAddMindfulness}
        />

        <GoalRow
          icon="🤸"
          label="ストレッチ"
          current={progress.stretchMinutesCompleted || 0}
          goal={goal.stretchMinutesGoal || 0}
          color="blue"
          unit="分"
          actionLabel="+1分"
          onAction={onAddStretch}
        />

        {/* Log Goal */}
        <div className="flex items-center space-x-3">
          <span className="text-xl">📝</span>
          <div className="flex-1">
            <p className="text-sm font-semibold text-gray-700">ログ記録</p>
            <div className="flex items-center space-x-2 mt-1">
              {goal.logGoal.mealRequired && (
                <LogBadge
                  label={goal.logGoal.mealKcalGoal ? `食事 ${progress.logProgress.mealKcalLogged || 0}/${goal.logGoal.mealKcalGoal}kcal` : '食事'}
                  completed={goal.logGoal.mealKcalGoal
                    ? (progress.logProgress.mealKcalLogged || 0) >= goal.logGoal.mealKcalGoal
                    : progress.logProgress.mealLogged}
                />
              )}
              {goal.logGoal.drinkRequired && (
                <LogBadge
                  label={goal.logGoal.drinkMlGoal ? `水分 ${progress.logProgress.drinkMlLogged || 0}/${goal.logGoal.drinkMlGoal}ml` : '飲み物'}
                  completed={goal.logGoal.drinkMlGoal
                    ? (progress.logProgress.drinkMlLogged || 0) >= goal.logGoal.drinkMlGoal
                    : progress.logProgress.drinkLogged}
                />
              )}
              {goal.logGoal.mindInputRequired && (
                <LogBadge
                  label="マインド"
                  completed={progress.logProgress.mindInputLogged}
                />
              )}
            </div>
          </div>
          {logCompletedCount >= logGoalsCount && (
            <span className="text-green-500 text-xl">✓</span>
          )}
        </div>

        {(goal.customActivities || []).length > 0 && (
          <div className="flex items-start space-x-3">
            <span className="text-xl">✨</span>
            <div className="flex-1">
              <p className="text-sm font-semibold text-gray-700">カスタム活動</p>
              <div className="flex flex-wrap gap-2 mt-1">
                {(goal.customActivities || []).map(activity => {
                  const completed = (progress.completedActivityIds || []).includes(activity.id);
                  return (
                    <button
                      key={activity.id}
                      onClick={() => onToggleCustomActivity?.(activity.id)}
                      className={`text-xs px-2 py-1 rounded-md font-semibold ${
                        completed ? 'bg-green-100 text-green-700' : 'bg-gray-100 text-gray-600'
                      }`}
                    >
                      {completed && '✓ '}{activity.emoji} {activity.title}
                    </button>
                  );
                })}
              </div>
            </div>
          </div>
        )}
      </div>

      {/* Edit Button */}
      <button
        onClick={onEdit}
        className="mt-4 w-full py-2 px-4 bg-duo-green-light hover:bg-green-100 text-duo-green-dark font-black rounded-xl transition-colors flex items-center justify-center space-x-2"
      >
        <span>✏️</span>
        <span>目標を編集</span>
      </button>
    </div>
  );
};

interface GoalRowProps {
  icon: string;
  label: string;
  current: number;
  goal: number;
  color: 'green' | 'purple' | 'blue';
  unit?: string;
  actionLabel?: string;
  onAction?: () => void;
}

const GoalRow: React.FC<GoalRowProps> = ({
  icon,
  label,
  current,
  goal,
  color,
  unit = '',
  actionLabel,
  onAction
}) => {
  const percentage = goal > 0 ? Math.min((current / goal) * 100, 100) : 0;
  const isComplete = current >= goal;

  const colorClasses = {
    green: 'bg-green-500',
    purple: 'bg-purple-500',
    blue: 'bg-blue-500'
  };

  if (goal <= 0) return null;

  return (
    <div className="flex items-center space-x-3">
      <span className="text-xl">{icon}</span>
      <div className="flex-1">
        <div className="flex items-center justify-between mb-1">
          <p className="text-sm font-semibold text-gray-700">{label}</p>
          <p
            className={`text-sm font-bold ${
              isComplete ? 'text-green-600' : 'text-gray-600'
            }`}
          >
            {current} / {goal}{unit}
          </p>
        </div>
        <div className="w-full bg-gray-200 rounded-full h-2">
          <div
            className={`h-2 rounded-full transition-all ${colorClasses[color]}`}
            style={{ width: `${percentage}%` }}
          />
        </div>
      </div>
      {onAction && (
        <button
          onClick={onAction}
          className="text-xs font-black text-duo-green bg-duo-green-light px-2 py-1 rounded-lg"
        >
          {actionLabel}
        </button>
      )}
      {isComplete && <span className="text-green-500 text-xl">✓</span>}
    </div>
  );
};

interface LogBadgeProps {
  label: string;
  completed: boolean;
}

const LogBadge: React.FC<LogBadgeProps> = ({ label, completed }) => {
  return (
    <span
      className={`text-xs px-2 py-1 rounded-md font-semibold ${
        completed
          ? 'bg-green-100 text-green-700'
          : 'bg-gray-100 text-gray-600'
      }`}
    >
      {completed && '✓ '}
      {label}
    </span>
  );
};

export default TimeSlotCard;
