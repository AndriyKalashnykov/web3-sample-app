import { useTranslation } from 'react-i18next'

const About = () => {
  const { t } = useTranslation()
  return (
    <div className="py-4 text-center whitespace-pre-line">
      <a href="https://www.google.com/">Web3 Sample App</a>
    </div>
  )
}
export default About
