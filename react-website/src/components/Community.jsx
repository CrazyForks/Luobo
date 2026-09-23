import { motion } from 'framer-motion'
import { Github } from 'lucide-react'
import FadeIn from './effects/FadeIn'
import GradientText from './effects/GradientText'
import './Community.css'

const cards = [
    {
        icon: Github,
        color: '#ffffff',
        label: 'Open Source',
        title: 'Contribute on GitHub',
        description: 'Report bugs, suggest features, submit pull requests, and shape the future of Musly.',
        actions: [
            { href: 'https://github.com/chengsitom/Luobo', label: 'View on GitHub', style: 'github' },
        ]
    },
]

export default function Community() {
    return (
        <section className="community section">
            <div className="container">
                {/* Header */}
                <FadeIn className="com-header">
                    <span className="section-tag">Community</span>
                    <h2 className="com-title">
                        Join the <GradientText>Musly</GradientText> Community
                    </h2>
                    <p className="com-subtitle">
                        Connect with other users, support the project, and help shape its future.
                    </p>
                </FadeIn>

                {/* Cards */}
                <div className="com-grid">
                    {cards.map((card, i) => (
                        <FadeIn key={card.label} delay={0.1 * i}>
                            <div className="com-card">
                                <div
                                    className="com-card-icon"
                                    style={{ background: `${card.color}18`, color: card.color }}
                                >
                                    <card.icon size={24} />
                                </div>
                                <span className="com-card-label" style={{ color: card.color }}>
                                    {card.label}
                                </span>
                                <h3 className="com-card-title">{card.title}</h3>
                                <p className="com-card-desc">{card.description}</p>

                                {card.actions.length > 0 && (
                                    <div className="com-card-actions">
                                        {card.actions.map(action => (
                                            <motion.a
                                                key={action.href}
                                                href={action.href}
                                                target="_blank"
                                                rel="noopener noreferrer"
                                                className={`btn com-btn com-btn--${action.style}`}
                                                whileHover={{ scale: 1.03 }}
                                                whileTap={{ scale: 0.97 }}
                                            >
                                                {action.style === 'github' && <Github size={16} />}
                                                {action.label}
                                            </motion.a>
                                        ))}
                                    </div>
                                )}
                            </div>
                        </FadeIn>
                    ))}
                </div>
            </div>
        </section>
    )
}
