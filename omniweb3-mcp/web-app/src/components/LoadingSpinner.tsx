interface LoadingSpinnerProps {
  message?: string
}

export default function LoadingSpinner({ message = 'Loading...' }: LoadingSpinnerProps) {
  return (
    <div className="py-8">
      <div className="animate-spin w-8 h-8 border-4 border-purple-500 border-t-transparent rounded-full mx-auto" />
      <p className="text-gray-400 mt-4">{message}</p>
    </div>
  )
}
