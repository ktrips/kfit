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
}

const TimeSlotCard: React.FC<TimeSlotCardProps> = ({
  timeSlot,
  goal,
  progress,
  onEdit
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
    <div className="bg-white rounded-lg shadow-md p-6">
      {/* Header */}
      <div className="flex items-center justify-between mb-4">
        <div className="flex items-center space-x-3">
          <span className="text-3xl">{info.emoji}</span>
          <div>
            <h3 className="text-xl font-bold text-gray-800">
              {info.displayName}
            </h3>
            <p className="text-sm text-gray-500">{info.timeRange}</p>
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
        />

        {/* Log Goal */}
        <div className="flex items-center space-x-3">
          <span className="text-xl">📝</span>
          <div className="flex-1">
            <p className="text-sm font-semibold text-gray-700">ログ記録</p>
            <div className="flex items-center space-x-2 mt-1">
              {goal.logGoal.mealRequired && (
                <LogBadge
                  label="食事"
                  completed={progress.logProgress.mealLogged}
                />
              )}
              {goal.logGoal.drinkRequired && (
                <LogBadge
                  label="飲み物"
                  completed={progress.logProgress.drinkLogged}
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
      </div>

      {/* Edit Button */}
      <button
        onClick={onEdit}
        className="mt-4 w-full py-2 px-4 bg-green-50 hover:bg-green-100 text-green-700 font-semibold rounded-lg transition-colors flex items-center justify-center space-x-2"
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
  color: 'green' | 'purple';
}

const GoalRow: React.FC<GoalRowProps> = ({
  icon,
  label,
  current,
  goal,
  color
}) => {
  const percentage = goal > 0 ? Math.min((current / goal) * 100, 100) : 0;
  const isComplete = current >= goal;

  const colorClasses = {
    green: 'bg-green-500',
    purple: 'bg-purple-500'
  };

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
            {current} / {goal}
          </p>
        </div>
        <div className="w-full bg-gray-200 rounded-full h-2">
          <div
            className={`h-2 rounded-full transition-all ${colorClasses[color]}`}
            style={{ width: `${percentage}%` }}
          />
        </div>
      </div>
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
