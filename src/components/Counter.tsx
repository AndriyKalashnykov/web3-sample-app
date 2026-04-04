import { useAppDispatch, useAppSelector } from '@/store'
import { increment } from '@/store/counterSlice'

export default function Counter() {
  const counter = useAppSelector((state) => state.counter)
  const dispatch = useAppDispatch()

  return (
    <>
      <div
        onClick={() => dispatch(increment(1))}
        className="py-2 text-center text-white rounded-sm bg-green-500 active:bg-green-300"
      >
        Click me - {counter}
      </div>
    </>
  )
}
