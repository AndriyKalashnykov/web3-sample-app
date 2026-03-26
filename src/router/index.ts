import { lazy } from 'react'

const Index = lazy(() => import('@/pages/index/index'))
const About = lazy(() => import('@/pages/about/index'))

const routes = [
  {
    path: '/',
    component: Index,
  },
  {
    path: '/about',
    component: About,
  },
]
export default routes
