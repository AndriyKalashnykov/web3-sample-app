import './index.css'
import AccountForm from '@/components/AccountForm'

const Index = () => {
  return (
    <>
      <div className="flex items-center justify-center h-20 text-secondary"></div>
      <div className="flex items-center justify-center h-32 text-secondary">
        <AccountForm />
      </div>
    </>
  )
}

export default Index
